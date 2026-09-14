# frozen_string_literal: true

module Sentry
  # @private
  module CallbackHelper
    # @!visibility private
    def safe_dispatch_callback(callback_name, callback, args, fallback: nil)
      callback.call(*args)
    rescue => e
      log_callback_error(callback_name, e)
      fallback
    end

    private

    def log_callback_error(callback_name, exception)
      return unless Sentry.initialized?

      message = "Error in #{callback_name} callback: #{exception.message}"
      message += "\n#{exception.backtrace.join("\n")}" if Sentry.configuration.debug && exception.backtrace

      Sentry.sdk_logger.error(LOGGER_PROGNAME) { message }
    rescue StandardError
      # Callback error reporting must not propagate to the application.
    end
  end
end
