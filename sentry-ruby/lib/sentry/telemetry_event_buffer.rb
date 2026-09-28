# frozen_string_literal: true

require "json"
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
    include CallbackHelper

    FLUSH_INTERVAL = 5 # seconds
    FLUSH_TIMEOUT = 2 # seconds

    # @!visibility private
    attr_reader :pending_items, :envelope_type, :data_category, :thread

    def initialize(configuration, client, event_class:, max_items:, max_items_before_drop:, envelope_type:, envelope_content_type:, before_send:)
      super(configuration.sdk_logger, FLUSH_INTERVAL)

      @client = client
      @configuration = configuration
      @dsn = configuration.dsn
      @debug = configuration.debug
      @event_class = event_class
      @max_items = max_items
      @max_items_before_drop = max_items_before_drop
      @envelope_type = envelope_type
      @data_category = Sentry::Envelope::Item.data_category(@envelope_type)
      @envelope_content_type = envelope_content_type
      @before_send = before_send

      @pending_items = []
      @mutex = Mutex.new

      log_debug("[#{self.class}] Initialized buffer with max_items=#{@max_items}, flush_interval=#{FLUSH_INTERVAL}s")
    end

    def flush
      return unless thread&.alive? && wake

      wait_until_idle(FLUSH_TIMEOUT)
    end

    def run
      flush_pending_items
    end

    def add_item(item)
      # the buffer thread can never add telemetry itself to prevent recursion
      return self if Thread.current == thread
      return unless ensure_thread

      # Prevent ThreadError from re-entrant locking (e.g. transport instrumentation calling Sentry.metrics.*)
      return self if @mutex.owned?

      dropped = false
      size_exceeded = @mutex.synchronize do
        if size >= @max_items_before_drop
          dropped = true
        else
          @pending_items << item
        end

        size >= @max_items
      end

      if dropped
        log_debug("[#{self.class}] exceeded max capacity, dropping event")
        @client.transport.record_lost_event(
          :queue_overflow,
          @data_category,
          num_bytes: JSON.generate(item.to_h).bytesize
        )
      end

      wake if size_exceeded
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

    def reset_if_forked
      return unless super

      # Discard items inherited from the parent to avoid duplicate delivery.
      @mutex = Mutex.new
      @pending_items = []
    end

    def flush_pending_items
      pending_items = @mutex.synchronize do
        next if @pending_items.empty?

        items = @pending_items
        @pending_items = []
        items
      end

      return unless pending_items

      log_debug("[#{self.class}] flushing #{pending_items.size} #{@event_class}")
      send_items(pending_items)
      self
    end

    def send_items(pending_items)
      envelope = Envelope.new(sent_at: Sentry.utc_now.iso8601)

      discarded_count = 0
      discarded_bytes = 0
      envelope_items = []

      if callback = @configuration.send(@before_send)
        pending_items.each do |item|
          processed_item = safe_dispatch_callback(@before_send.to_s, callback, [item])

          if processed_item
            envelope_items << processed_item.to_h
          else
            discarded_count += 1
            discarded_bytes += JSON.generate(item.to_h).bytesize
          end
        end
      else
        envelope_items = pending_items.map(&:to_h)
      end

      unless discarded_count.zero?
        @client.transport.record_lost_event(:before_send, @data_category, num: discarded_count, num_bytes: discarded_bytes)
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
      log_error("[#{self.class}] Failed to send #{@event_class}", e, debug: @debug)
    end
  end
end
