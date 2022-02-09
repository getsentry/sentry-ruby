require 'securerandom'

module Sentry
  class Session
    # TODO-neel docs, types
    attr_accessor :sid
    attr_accessor :did
    attr_accessor :timestamp
    attr_accessor :started
    attr_accessor :duration
    attr_accessor :status
    attr_accessor :release
    attr_accessor :environment
    attr_accessor :user_agent
    attr_accessor :ip_address
    attr_accessor :errors
    attr_accessor :user
    attr_accessor :mode

    def initialize(mode: :request, **options)
      @mode = mode
      @sid = options[:sid] || SecureRandom.uuid.delete('-')
      @started = options[:started] || Sentry.utc_now
      @status = options[:status] || :ok

      update(options)
    end

    def update(**options)
    end

    def close(status: :exited)
      @status = status
    end

    def deep_dup
      dup
    end
  end
end
