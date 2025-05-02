# frozen_string_literal: true

require "sentry/threaded_periodic_worker"

module Sentry
  class LogEventBuffer < ThreadedPeriodicWorker
    FLUSH_INTERVAL = 5 # seconds
    DEFAULT_MAX_EVENTS = 100

    def initialize(configuration, client)
      super(configuration.logger, FLUSH_INTERVAL)
      @client = client
      @pending_events = []
      @max_events = configuration.max_log_events || DEFAULT_MAX_EVENTS
      @dsn = configuration.dsn
      @sdk = Sentry.sdk_meta
      @mutex = Mutex.new

      log_debug("[LogEvents] Initialized buffer with max_events=#{@max_events}, flush_interval=#{FLUSH_INTERVAL}s")
    end

    def start
      ensure_thread
      self
    end

    def flush
      @mutex.synchronize do
        return unless size >= @max_events

        log_debug("[LogEventBuffer] flushing #{size} log events")

        @client.send_envelope(to_envelope)

        @pending_events.clear
      end

      log_debug("[LogEventBuffer] flushed #{size} log events")

      self
    end

    def add_event(event)
      raise ArgumentError, "expected a LogEvent, got #{event.class}" unless event.is_a?(LogEvent)

      @mutex.synchronize do
        @pending_events << event
      end

      self
    end

    def empty?
      @pending_events.empty?
    end

    def size
      @pending_events.size
    end

    alias_method :run, :flush

    private

    def to_envelope
      envelope = Envelope.new(
        event_id: SecureRandom.uuid.delete("-"),
        sent_at: Sentry.utc_now.iso8601,
        dsn: @dsn,
        sdk: @sdk
      )

      envelope.add_item(
        {
          type: "log",
          item_count: size,
          content_type: "application/vnd.sentry.items.log+json"
        },
        { items: @pending_events.map(&:to_hash) }
      )

      envelope
    end
  end
end
