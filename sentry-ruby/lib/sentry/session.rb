# frozen_string_literal: true

module Sentry
  class Session
    attr_reader :started, :status, :aggregation_key

    STATUSES = %i[ok errored crashed exited]
    AGGREGATE_STATUSES = %i[errored crashed exited]

    def initialize
      @started = Sentry.utc_now
      @status = :ok

      # truncate seconds from the timestamp since we only care about
      # minute level granularity for aggregation
      @aggregation_key = Time.utc(@started.year, @started.month, @started.day, @started.hour, @started.min)
    end

    def update_from_error_event(event)
      return unless event.is_a?(ErrorEvent) && event.exception

      crashed = event.exception.values.any? { |e| e.mechanism.handled == false }
      @status = crashed ? :crashed : :errored
    end

    def close
      @status = :exited if @status == :ok
    end

    def deep_dup
      dup
    end
  end
end
