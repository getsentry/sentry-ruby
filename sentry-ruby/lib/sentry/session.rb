require 'securerandom'

module Sentry
  class Session
    # TODO-neel docs, types
    attr_accessor :started
    attr_accessor :status
    attr_accessor :errors

    def initialize
      @started = Sentry.utc_now
      @status = :ok
      @errors = 0
    end

    def update_from_event(event)
      return unless event
    end

    def close(status: :exited)
      @status = status
    end

    def deep_dup
      dup
    end
  end
end
