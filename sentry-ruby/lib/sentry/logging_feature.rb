# frozen_string_literal: true

module Sentry
  module LoggingFeature
    def self.setup
      Sentry.logger.extend(LoggerMethods)
    end

    module LoggerMethods
      def log_with_sentry(level, message, **attributes)
        Sentry.capture_log(message, level: level, **attributes)
      end
    end
  end
end
