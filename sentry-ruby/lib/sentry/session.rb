# frozen_string_literal: true

module Sentry
  class Session
    attr_reader :started, :status

    # TODO-neel add :crashed after adding handled mechanism
    STATUSES = %i(ok errored exited)
    AGGREGATE_STATUSES = %i(errored exited)

    def initialize
      @started = Sentry.utc_now
      @status = :ok
    end

    # TODO-neel add :crashed after adding handled mechanism
    def update_from_exception(_exception = nil)
      @status = :errored
    end

    def close
      @status = :exited if @status == :ok
    end

    # truncate seconds from the timestamp since we only care about
    # minute level granularity for aggregation
    def aggregation_key
      Time.utc(started.year, started.month, started.day, started.hour, started.min)
    end

    def deep_dup
      dup
    end
  end
end
