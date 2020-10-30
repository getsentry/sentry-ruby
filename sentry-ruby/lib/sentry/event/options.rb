module Sentry
  class Event
    class Options
      attr_reader :message,
        :user, :extra, :tags, :contexts,
        :backtrace, :level, :fingerprint,
        :server_name, :release, :environment

      def initialize(
        message: "",
        user: {}, extra: {}, tags: {}, contexts: {},
        backtrace: [], level: :error, fingerprint: [],
        # nilable attributes because we'll fallback to the configuration's values
        server_name: nil, release: nil, environment: nil
      )
        @message = message || ""
        @user = user || {}
        @extra = extra || {}
        @tags = tags || {}
        @contexts = contexts || {}
        @backtrace = backtrace || []
        @fingerprint = fingerprint || []
        @level = level || :error
        @server_name = server_name
        @environment = environment
        @release = release
      end
    end
  end
end

