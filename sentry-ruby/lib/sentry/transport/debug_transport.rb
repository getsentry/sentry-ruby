# frozen_string_literal: true

require "json"
require "fileutils"
require "pathname"
require "delegate"

module Sentry
  # DebugTransport is a transport that logs events to a file for debugging purposes.
  #
  # It can optionally also send events to Sentry via HTTP transport if a real DSN
  # is provided.
  class DebugTransport < SimpleDelegator
    DEFAULT_LOG_FILE_PATH = File.join("log", "sentry_debug_events.log")

    attr_reader :log_file, :backend

    def initialize(configuration)
      @log_file = initialize_log_file(configuration)
      @backend = initialize_backend(configuration)

      super(@backend)
    end

    def send_event(event)
      log_envelope(envelope_from_event(event))
      backend.send_event(event)
    end

    def log_envelope(envelope)
      envelope_json = {
        timestamp: Time.now.utc.iso8601,
        envelope_headers: envelope.headers,
        items: envelope.items.map do |item|
          { headers: item.headers, payload: item.payload }
        end
      }

      File.open(log_file, "a") { |file| file << JSON.dump(envelope_json) << "\n" }
    end

    def logged_envelopes
      return [] unless File.exist?(log_file)

      File.readlines(log_file).map do |line|
        JSON.parse(line)
      end
    end

    def clear
      File.write(log_file, "")
      log_debug("DebugTransport: Cleared events from #{log_file}")
    end

    private

    def initialize_backend(configuration)
      backend = configuration.dsn.local? ? DummyTransport : HTTPTransport
      backend.new(configuration)
    end

    def initialize_log_file(configuration)
      log_file = Pathname(configuration.sdk_debug_transport_log_file || DEFAULT_LOG_FILE_PATH)

      FileUtils.mkdir_p(log_file.dirname) unless log_file.dirname.exist?

      log_file
    end
  end
end
