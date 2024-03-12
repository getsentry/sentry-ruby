# frozen_string_literal: true

module Sentry
  module Metrics
    class Aggregator
      include LoggingHelper

      FLUSH_INTERVAL = 5
      ROLLUP_IN_SECONDS = 10

      KEY_SANITIZATION_REGEX = /[^a-zA-Z0-9_\/.-]+/
      VALUE_SANITIZATION_REGEX = /[^[[:word:]][[:digit:]][[:space:]]_:\/@\.{}\[\]$-]+/

      METRIC_TYPES = {
        c: CounterMetric,
        d: DistributionMetric,
        g: GaugeMetric,
        s: SetMetric
      }

      # exposed only for testing
      attr_reader :thread, :buckets, :flush_shift

      def initialize(configuration, client)
        @client = client
        @logger = configuration.logger
        @before_emit = configuration.metrics.before_emit

        @default_tags = {}
        @default_tags['release'] = configuration.release if configuration.release
        @default_tags['environment'] = configuration.environment if configuration.environment

        @thread = nil
        @exited = false
        @mutex = Mutex.new

        # buckets are a nested hash of timestamp -> bucket keys -> Metric instance
        @buckets = {}

        # the flush interval needs to be shifted once per startup to create jittering
        @flush_shift = Random.rand * ROLLUP_IN_SECONDS
      end

      def add(type,
              key,
              value,
              unit: 'none',
              tags: {},
              timestamp: nil)
        return unless ensure_thread
        return unless METRIC_TYPES.keys.include?(type)

        timestamp = timestamp.to_i if timestamp.is_a?(Time)
        timestamp ||= Sentry.utc_now.to_i

        # this is integer division and thus takes the floor of the division
        # and buckets into 10 second intervals
        bucket_timestamp = (timestamp / ROLLUP_IN_SECONDS) * ROLLUP_IN_SECONDS
        updated_tags = get_updated_tags(tags)

        return if @before_emit && !@before_emit.call(key, updated_tags)

        serialized_tags = serialize_tags(updated_tags)
        bucket_key = [type, key, unit, serialized_tags]

        added = @mutex.synchronize do
          @buckets[bucket_timestamp] ||= {}

          if (metric = @buckets[bucket_timestamp][bucket_key])
            old_weight = metric.weight
            metric.add(value)
            metric.weight - old_weight
          else
            metric = METRIC_TYPES[type].new(value)
            @buckets[bucket_timestamp][bucket_key] = metric
            metric.weight
          end
        end

        # for sets, we pass on if there was a new entry to the local gauge
        local_value = type == :s ? added : value
        process_span_aggregator(bucket_key, local_value)
      end

      def flush(force: false)
        flushable_buckets = get_flushable_buckets!(force)
        return if flushable_buckets.empty?

        payload = serialize_buckets(flushable_buckets)
        envelope = Envelope.new
        envelope.add_item(
          { type: 'statsd', length: payload.bytesize },
          payload
        )

        Sentry.background_worker.perform do
          @client.transport.send_envelope(envelope)
        end
      end

      def kill
        log_debug('[Metrics::Aggregator] killing thread')

        @exited = true
        @thread&.kill
      end

      private

      def ensure_thread
        return false if @exited
        return true if @thread&.alive?

        @thread = Thread.new do
          loop do
            # TODO-neel-metrics use event for force flush later
            sleep(FLUSH_INTERVAL)
            flush
          end
        end

        true
      rescue ThreadError
        log_debug('[Metrics::Aggregator] thread creation failed')
        @exited = true
        false
      end

      # important to sort for key consistency
      def serialize_tags(tags)
        tags.flat_map do |k, v|
          if v.is_a?(Array)
            v.map { |x| [k.to_s, x.to_s] }
          else
            [[k.to_s, v.to_s]]
          end
        end.sort
      end

      def get_flushable_buckets!(force)
        @mutex.synchronize do
          flushable_buckets = {}

          if force
            flushable_buckets = @buckets
            @buckets = {}
          else
            cutoff = Sentry.utc_now.to_i - ROLLUP_IN_SECONDS - @flush_shift
            flushable_buckets = @buckets.select { |k, _| k <= cutoff }
            @buckets.reject! { |k, _| k <= cutoff }
          end

          flushable_buckets
        end
      end

      # serialize buckets to statsd format
      def serialize_buckets(buckets)
        buckets.map do |timestamp, timestamp_buckets|
          timestamp_buckets.map do |metric_key, metric|
            type, key, unit, tags = metric_key
            values = metric.serialize.join(':')
            sanitized_tags = tags.map { |k, v| "#{sanitize_key(k)}:#{sanitize_value(v)}" }.join(',')

            "#{sanitize_key(key)}@#{unit}:#{values}|#{type}|\##{sanitized_tags}|T#{timestamp}"
          end
        end.flatten.join("\n")
      end

      def sanitize_key(key)
        key.gsub(KEY_SANITIZATION_REGEX, '_')
      end

      def sanitize_value(value)
        value.gsub(VALUE_SANITIZATION_REGEX, '')
      end

      def get_transaction_name
        scope = Sentry.get_current_scope
        return nil unless scope && scope.transaction_name
        return nil if scope.transaction_source_low_quality?

        scope.transaction_name
      end

      def get_updated_tags(tags)
        updated_tags = @default_tags.merge(tags)

        transaction_name = get_transaction_name
        updated_tags['transaction'] = transaction_name if transaction_name

        updated_tags
      end

      def process_span_aggregator(key, value)
        scope = Sentry.get_current_scope
        return nil unless scope && scope.span
        return nil if scope.transaction_source_low_quality?

        scope.span.metrics_local_aggregator.add(key, value)
      end
    end
  end
end
