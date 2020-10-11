module Sentry
  class Event
    class Options
      attr_reader :message,
        :user, :extra, :tags, :contexts,
        :backtrace, :level, :checksum, :fingerprint,
        :server_name, :release, :environment,
        :time_spent

      def initialize(
        message: "",
        user: {}, extra: {}, tags: {}, contexts: {},
        backtrace: [], level: :error, checksum: "", fingerprint: [],
        # nilable attributes because we'll fallback to the configuration's values
        server_name: nil, release: nil, environment: nil,
        time_spent: nil
      )
        @message = message || ""
        @user = user || {}
        @extra = extra || {}
        @tags = tags || {}
        @contexts = contexts || {}
        @backtrace = backtrace || []
        @fingerprint = fingerprint || []
        @level = level || :error
        @checksum = checksum || ""
        @server_name = server_name
        @environment = environment
        @release = release
        @time_spent = time_spent
      end
    end
  end
end

