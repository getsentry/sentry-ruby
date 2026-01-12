# frozen_string_literal: true

require "sentry/threaded_periodic_worker"
require "sentry/envelope"

module Sentry
  # TelemetryEventBuffer is a base class for buffering telemetry events (logs, metrics, etc.)
  # and sending them to Sentry in a single envelope.
  #
  # This is used internally by the `Sentry::Client`.
  #
  # @!visibility private
  class TelemetryEventBuffer < ThreadedPeriodicWorker
    FLUSH_INTERVAL = 5 # seconds

    # @!visibility private
    attr_reader :pending_items

    def initialize(configuration, client, event_class:, max_items:, envelope_type:, envelope_content_type:, before_send:)
      super(configuration.sdk_logger, FLUSH_INTERVAL)

      @client = client
      @dsn = configuration.dsn
      @event_class = event_class
      @max_items = max_items
      @envelope_type = envelope_type
      @envelope_content_type = envelope_content_type
      @before_send = before_send

      @pending_items = []
      @mutex = Mutex.new

      log_debug("[] Initialized buffer with max_items=#{@max_items}, flush_interval=#{FLUSH_INTERVAL}s")
    end

    def start
      ensure_thread
      self
    end

    def flush
      @mutex.synchronize do
        return if empty?

        log_debug("[#{self.class.name}] flushing #{size} #{@event_class}")

        send_items
      end

      self
    end
    alias_method :run, :flush

    def add_item(item)
      raise ArgumentError, "expected a #{@event_class}, got #{item.class}" unless item.is_a?(@event_class)

      @mutex.synchronize do
        @pending_items << item
        send_items if size >= @max_items
      end

      self
    end

    def empty?
      @pending_items.empty?
    end

    def size
      @pending_items.size
    end

    def clear!
      @pending_items.clear
    end

    private

    def send_items
      envelope = Envelope.new(
        event_id: Sentry::Utils.uuid,
        sent_at: Sentry.utc_now.iso8601,
        dsn: @dsn,
        sdk: Sentry.sdk_meta
      )

      discarded_count = 0
      envelope_items = []

      if @before_send
        @pending_items.each do |item|
          processed_item = @before_send.call(item)

          if processed_item
            envelope_items << processed_item.to_h
          else
            discarded_count += 1
          end
        end
      else
        envelope_items = @pending_items.map(&:to_h)
      end

      unless discarded_count.zero?
        @data_category = Sentry::Envelope::Item.data_category(@envelope_type)
        @client.transport.record_lost_event(:before_send, @data_category, num: discarded_count)
      end

      return if envelope_items.empty?

      envelope.add_item(
        {
          type: @envelope_type,
          item_count: envelope_items.size,
          content_type: @envelope_content_type
        },
        { items: envelope_items }
      )

      @client.send_envelope(envelope)
    rescue => e
      log_debug("[#{self.class.name}] Failed to send #{@event_class}: #{e.message}")
    ensure
      clear!
    end
  end
end
