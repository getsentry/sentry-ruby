# frozen_string_literal: true

module Sentry
  # @private
  module LoggingHelper
    # @!visibility private
    def log_error(message, exception, debug: false)
      message = "#{message}: #{exception.message}"
      message += "\n#{exception.backtrace.join("\n")}" if debug && exception.backtrace

      sdk_logger&.error(LOGGER_PROGNAME) { message }
    rescue StandardError => e
      $stderr.puts "Sentry SDK logging failed (#{e.class}: #{e.message})"
    end

    # @!visibility private
    def log_debug(message)
      sdk_logger&.debug(LOGGER_PROGNAME) { message }
    rescue StandardError => e
      $stderr.puts "Sentry SDK logging failed (#{e.class}: #{e.message})"
    end

    # @!visibility private
    def log_warn(message)
      sdk_logger&.warn(LOGGER_PROGNAME) { message }
    rescue StandardError => e
      $stderr.puts "Sentry SDK logging failed (#{e.class}: #{e.message})"
    end

    # @!visibility private
    def sdk_logger
      @sdk_logger ||= Sentry.sdk_logger
    end
  end
end
