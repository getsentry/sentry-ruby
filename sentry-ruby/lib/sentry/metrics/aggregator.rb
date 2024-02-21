# frozen_string_literal: true

module Sentry
  module Metrics
    class Aggregator
      include LoggingHelper

      FLUSH_INTERVAL = 5
      ROLLUP_IN_SECONDS = 10

      METRIC_TYPES = {
        c: CounterMetric,
        d: DistributionMetric,
        g: GaugeMetric,
        s: SetMetric
      }

      def initialize(configuration, client)
        @client = client
        @logger = configuration.logger
        @release = configuration.release
        @environment = configuration.environment

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
              unit,
              tags: nil,
              timestamp: nil)
        return unless ensure_thread

        timestamp = timestamp.to_i if timestamp.is_a?(Time)
        timestamp ||= Sentry.utc_now.to_i

        # this is integer division and thus takes the floor of the division
        # and buckets into 10 second intervals
        bucket_timestamp = (timestamp / ROLLUP_IN_SECONDS) * ROLLUP_IN_SECONDS

        serialized_tags = serialize_tags(tags)
        bucket_key = [type, key, unit, serialized_tags]

        @mutex.synchronize do
          @buckets[bucket_timestamp] ||= {}

          if @buckets[bucket_timestamp][bucket_key]
            @buckets[bucket_timestamp][bucket_key].add(value)
          else
            @buckets[bucket_timestamp][bucket_key] = METRIC_TYPES[type].new(value)
          end
        end
      end

      def flush
        @mutex.synchronize do
          log_debug("[Metrics::Aggregator] current bucket state: #{@buckets}")
          # TODO
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
            # TODO use event for force flush later
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

      def serialize_tags(tags)
        return [] unless tags

        # important to sort for key consistency
        tags.map do |k, v|
          if v.is_a?(Array)
            v.map { |x| [k.to_s, x.to_s] }
          else
            [k.to_s, v.to_s]
          end
        end.flatten.sort
      end
    end
  end
end
