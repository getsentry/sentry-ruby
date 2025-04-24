module Sentry
  module Logging
    class Handler
      # https://develop.sentry.dev/sdk/telemetry/logs/#log-severity-number
      LEVELS = {
        "trace" => 1,
        "debug" => 5,
        "info" => 9,
        "warn" => 13,
        "error" => 17,
        "fatal" => 21
      }.freeze

      attr_reader :config

      def initialize(config)
        @config = config
      end

      def info(message, payload = {})
        Sentry.capture_log(message, level: :info, severity: LEVELS[payload[:level]], **payload)
      end
    end
  end
end
