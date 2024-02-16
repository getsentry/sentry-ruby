# frozen_string_literal: true

module Sentry
  module Metrics
    class Aggregator
      include LoggingHelper

      FLUSH_INTERVAL = 5
      ROLLUP_IN_SECONDS = 10

      def initialize(configuration, client)
        @client = client
        @logger = configuration.logger
        @release = configuration.release
        @environment = configuration.environment

        @thread = nil
        @exited = false

        @buckets = {}
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

        # TODO lock and add to bucket
        42
      end

      def flush
        # TODO
      end

      def kill
        log_debug("[Metrics::Aggregator] killing thread")

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
        log_debug("[Metrics::Aggregator] thread creation failed")
        @exited = true
        false
      end

      def serialize_tags(tags)
        # TODO support array tags
        return [] unless tags
        tags.map { |k, v| [k.to_s, v.to_s] }
      end
    end
  end
end
