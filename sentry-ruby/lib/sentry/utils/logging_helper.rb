# frozen_string_literal: true

module Sentry
  # @private
  module LoggingHelper
    # @!visibility private
    def log_error(message, exception, debug: false)
      message = "#{message}: #{exception.message}"
      message += "\n#{exception.backtrace.join("\n")}" if debug

      Sentry.sdk_logger&.error(LOGGER_PROGNAME) do
        message
      end
    end

    # @!visibility private
    def log_debug(message)
      Sentry.sdk_logger&.debug(LOGGER_PROGNAME) { message }
    end

    # @!visibility private
    def log_warn(message)
      Sentry.sdk_logger&.warn(LOGGER_PROGNAME) { message }
    end
  end
end
