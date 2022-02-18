# frozen_string_literal: true

module Sentry
  class Session
    attr_reader :started, :status

    # TODO-neel add :crashed after adding handled
    STATUSES = %i(ok errored exited)
    AGGREGATE_STATUSES = %i(errored exited)

    def initialize
      @started = Sentry.utc_now
      @status = :ok
    end

    def update_from_event(event)
      return unless event.is_a?(Event) && event.exception
      @status = :errored
    end

    def close
      @status = :exited if @status == :ok
    end

    # truncate seconds from the timestamp since we only care about
    # minute level granularity for aggregation
    def started_bucket
      Time.utc(started.year, started.month, started.day, started.hour, started.min)
    end

    def deep_dup
      dup
    end
  end
end
