# frozen_string_literal: true

require "json"
require "fileutils"
require "pathname"
require "tempfile"
require "delegate"

module Sentry
  class DebugLogFile
    attr_reader :path

    def initialize(path, prefix)
      unless path
        @temporary_file = Tempfile.new([prefix, ".log"])
        @temporary_file.close
      end

      @path = Pathname(path || @temporary_file.path)
      @offset = 0
      @generation = nil
      FileUtils.mkdir_p(@path.dirname) unless @path.dirname.exist?
    end

    def append(entry)
      json = "#{JSON.dump(entry)}\n"
      File.open(path, "a") do |file|
        file.flock(File::LOCK_EX)
        file.write(json)
      end
    end

    def entries
      return [] unless path.exist?

      lines = File.open(path, "r") do |file|
        file.flock(File::LOCK_SH)
        current_generation = file.stat.ino
        @offset = 0 if @generation != current_generation
        @generation = current_generation
        file.seek(@offset)
        file.readlines
      end

      lines.select { |line| line.end_with?("\n") }.map { |line| JSON.parse(line) }
    end

    def clear
      File.open(path, "a") do |file|
        file.flock(File::LOCK_SH)
        @offset = file.size
        @generation = file.stat.ino
      end
    end

    def start_run
      return if @temporary_file

      File.open(path, "a") do |file|
        file.flock(File::LOCK_EX)
        previous = Pathname("#{path}.1")
        previous.rename("#{path}.2") if previous.exist?
        path.rename("#{path}.1")
        FileUtils.touch(path)
      end
      @offset = 0
      @generation = nil
    end
  end

  # DebugTransport is a transport that logs events to a file for debugging purposes.
  #
  # It can optionally also send events to Sentry via HTTP transport if a real DSN
  # is provided.
  class DebugTransport < SimpleDelegator
    DEFAULT_LOG_FILE_PATH = File.join("log", "sentry_debug_events.log")

    attr_reader :log_file, :backend

    def initialize(configuration)
      @log = DebugLogFile.new(configuration.sdk_debug_transport_log_file, File.basename(DEFAULT_LOG_FILE_PATH, ".log"))
      @log_file = @log.path
      @backend = initialize_backend(configuration)

      super(@backend)
    end

    def send_event(event)
      log_envelope(envelope_from_event(event))
      backend.send_event(event)
    end

    def send_envelope(envelope)
      log_envelope(envelope)
      backend.send_envelope(envelope)
    end

    def log_envelope(envelope)
      envelope_json = {
        timestamp: Time.now.utc.iso8601,
        envelope_headers: envelope.headers,
        items: envelope.items.map do |item|
          { headers: item.headers, payload: item.payload }
        end
      }

      @log.append(envelope_json)
    end

    def logged_envelopes
      @log.entries
    end

    def start_run
      @log.start_run
    end

    def clear
      @log.clear
      log_debug("DebugTransport: Cleared events from #{log_file}")
    end

    private

    def initialize_backend(configuration)
      backend = configuration.dsn.local? ? DummyTransport : HTTPTransport
      backend.new(configuration)
    end
  end
end
