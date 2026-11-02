# frozen_string_literal: true

require "sentry/transport/debug_transport"
require "delegate"

module Sentry
  # DebugStructuredLogger is a logger that captures structured log events to a file for debugging purposes.
  #
  # It also sends log events to Sentry via the normal structured logger.
  class DebugStructuredLogger < SimpleDelegator
    DEFAULT_LOG_FILE_PATH = File.join("log", "sentry_debug_logs.log")

    attr_reader :log_file, :backend

    def initialize(configuration)
      @log = DebugLogFile.new(configuration.structured_logging.file_path, File.basename(DEFAULT_LOG_FILE_PATH, ".log"))
      @log_file = @log.path
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

      @log.append(log_event_json)
      log_event_json
    end

    def logged_events
      @log.entries
    end

    def start_run
      @log.start_run
    end

    def clear
      @log.clear
      if backend.respond_to?(:config)
        backend.config.sdk_logger.debug("DebugStructuredLogger: Cleared events from #{log_file}")
      end
    end

    private

    def initialize_backend(configuration)
      StructuredLogger.new(configuration)
    end
  end
end
