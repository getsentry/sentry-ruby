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

      def trace(message, payload = {})
        log(:trace, message, payload)
      end

      def debug(message, payload = {})
        log(:debug, message, payload)
      end

      def info(message, payload = {})
        log(:info, message, payload)
      end

      def warn(message, payload = {})
        log(:warn, message, payload)
      end

      def error(message, payload = {})
        log(:error, message, payload)
      end

      def fatal(message, payload = {})
        log(:fatal, message, payload)
      end

      def log(level, message, payload)
        Sentry.capture_log(message, level: level, severity: LEVELS[level], **payload)
      end
    end
  end
end
