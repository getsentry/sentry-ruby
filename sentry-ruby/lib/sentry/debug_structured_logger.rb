# frozen_string_literal: true

require "json"
require "fileutils"
require "pathname"
require "delegate"

module Sentry
  # DebugStructuredLogger is a logger that captures structured log events to a file for debugging purposes.
  #
  # It can optionally also send log events to Sentry via the normal structured logger if logging
  # is enabled.
  class DebugStructuredLogger < SimpleDelegator
    DEFAULT_LOG_FILE_PATH = File.join("log", "sentry_debug_logs.log")

    attr_reader :log_file, :backend

    def initialize(configuration)
      @log_file = initialize_log_file(
        configuration.structured_logging.file_path || DEFAULT_LOG_FILE_PATH
      )
      @backend = initialize_backend(configuration)

      super(@backend)
    end

    # Override all log level methods to capture events
    %i[trace debug info warn error fatal].each do |level|
      define_method(level) do |message, parameters = [], **attributes|
        log_event = capture_log_event(level, message, parameters, **attributes)
        backend.public_send(level, message, parameters, **attributes)
        log_event
      end
    end

    def log(level, message, parameters:, **attributes)
      log_event = capture_log_event(level, message, parameters, **attributes)
      backend.log(level, message, parameters: parameters, **attributes)
      log_event
    end

    def capture_log_event(level, message, parameters, **attributes)
      log_event_json = {
        timestamp: Time.now.utc.iso8601,
        level: level.to_s,
        message: message,
        parameters: parameters,
        attributes: attributes
      }

      File.open(log_file, "a") { |file| file << JSON.dump(log_event_json) << "\n" }
      log_event_json
    end

    def logged_events
      File.readlines(log_file).map do |line|
        JSON.parse(line)
      end
    end

    def clear
      File.write(log_file, "")
      if backend.respond_to?(:config)
        backend.config.sdk_logger.debug("DebugStructuredLogger: Cleared events from #{log_file}")
      end
    end

    private

    def initialize_backend(configuration)
      if configuration.enable_logs
        StructuredLogger.new(configuration)
      else
        # Create a no-op logger if logging is disabled
        NoOpLogger.new
      end
    end

    def initialize_log_file(log_file_path)
      log_file = Pathname(log_file_path)

      FileUtils.mkdir_p(log_file.dirname) unless log_file.dirname.exist?

      log_file
    end

    # No-op logger for when structured logging is disabled
    class NoOpLogger
      %i[trace debug info warn error fatal log].each do |method|
        define_method(method) { |*args, **kwargs| nil }
      end
    end
  end
end
