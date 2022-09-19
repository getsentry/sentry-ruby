# frozen_string_literal: true

require "json"
require "base64"
require "sentry/envelope"

module Sentry
  class Transport
    PROTOCOL_VERSION = '7'
    USER_AGENT = "sentry-ruby/#{Sentry::VERSION}"
    CLIENT_REPORT_INTERVAL = 30

    # https://develop.sentry.dev/sdk/client-reports/#envelope-item-payload
    CLIENT_REPORT_REASONS = [
      :ratelimit_backoff,
      :queue_overflow,
      :cache_overflow, # NA
      :network_error,
      :sample_rate,
      :before_send,
      :event_processor
    ]

    include LoggingHelper

    attr_reader :rate_limits, :discarded_events, :last_client_report_sent

    # @deprecated Use Sentry.logger to retrieve the current logger instead.
    attr_reader :logger

    def initialize(configuration)
      @logger = configuration.logger
      @transport_configuration = configuration.transport
      @dsn = configuration.dsn
      @rate_limits = {}
      @send_client_reports = configuration.send_client_reports

      if @send_client_reports
        @discarded_events = Hash.new(0)
        @last_client_report_sent = Time.now
      end
    end

    def send_data(data, options = {})
      raise NotImplementedError
    end

    def send_event(event)
      envelope = envelope_from_event(event)
      send_envelope(envelope)

      event
    end

    def send_envelope(envelope)
      reject_rate_limited_items(envelope)

      return if envelope.items.empty?

      data, serialized_items = serialize_envelope(envelope)

      if data
        log_info("[Transport] Sending envelope with items [#{serialized_items.map(&:type).join(', ')}] #{envelope.event_id} to Sentry")
        send_data(data)
      end
    end

    def serialize_envelope(envelope)
      serialized_items = []
      serialized_results = []

      envelope.items.each do |item|
        result, oversized = item.serialize

        if oversized
          log_info("Envelope item [#{item.type}] is still oversized after size reduction: {#{item.size_breakdown}}")

          next
        end

        serialized_results << result
        serialized_items << item
      end

      data = [JSON.generate(envelope.headers), *serialized_results].join("\n") unless serialized_results.empty?

      [data, serialized_items]
    end

    def is_rate_limited?(item_type)
      # check category-specific limit
      category_delay =
        case item_type
        when "transaction"
          @rate_limits["transaction"]
        when "sessions"
          @rate_limits["session"]
        else
          @rate_limits["error"]
        end

      # check universal limit if not category limit
      universal_delay = @rate_limits[nil]

      delay =
        if category_delay && universal_delay
          if category_delay > universal_delay
            category_delay
          else
            universal_delay
          end
        elsif category_delay
          category_delay
        else
          universal_delay
        end

      !!delay && delay > Time.now
    end

    def generate_auth_header
      now = Sentry.utc_now.to_i
      fields = {
        'sentry_version' => PROTOCOL_VERSION,
        'sentry_client' => USER_AGENT,
        'sentry_timestamp' => now,
        'sentry_key' => @dsn.public_key
      }
      fields['sentry_secret'] = @dsn.secret_key if @dsn.secret_key
      'Sentry ' + fields.map { |key, value| "#{key}=#{value}" }.join(', ')
    end

    def envelope_from_event(event)
      # Convert to hash
      event_payload = event.to_hash
      event_id = event_payload[:event_id] || event_payload["event_id"]
      item_type = event_payload[:type] || event_payload["type"]

      envelope_headers = {
        event_id: event_id,
        dsn: @dsn.to_s,
        sdk: Sentry.sdk_meta,
        sent_at: Sentry.utc_now.iso8601
      }

      if event.is_a?(TransactionEvent) && event.dynamic_sampling_context
        envelope_headers[:trace] = event.dynamic_sampling_context
      end

      envelope = Envelope.new(envelope_headers)

      envelope.add_item(
        { type: item_type, content_type: 'application/json' },
        event_payload
      )

      client_report_headers, client_report_payload = fetch_pending_client_report
      envelope.add_item(client_report_headers, client_report_payload) if client_report_headers

      envelope
    end

    def record_lost_event(reason, item_type)
      return unless @send_client_reports
      return unless CLIENT_REPORT_REASONS.include?(reason)

      @discarded_events[[reason, item_type]] += 1
    end

    private

    def fetch_pending_client_report
      return nil unless @send_client_reports
      return nil if @last_client_report_sent > Time.now - CLIENT_REPORT_INTERVAL
      return nil if @discarded_events.empty?

      discarded_events_hash = @discarded_events.map do |key, val|
        reason, type = key

        # 'event' has to be mapped to 'error'
        category = type == 'transaction' ? 'transaction' : 'error'

        { reason: reason, category: category, quantity: val }
      end

      item_header = { type: 'client_report' }
      item_payload = {
        timestamp: Sentry.utc_now.iso8601,
        discarded_events: discarded_events_hash
      }

      @discarded_events = Hash.new(0)
      @last_client_report_sent = Time.now

      [item_header, item_payload]
    end

    def reject_rate_limited_items(envelope)
      envelope.items.reject! do |item|
        if is_rate_limited?(item.type)
          log_info("[Transport] Envelope item [#{item.type}] not sent: rate limiting")
          record_lost_event(:ratelimit_backoff, item.type)

          true
        else
          false
        end
      end
    end
  end
end

require "sentry/transport/dummy_transport"
require "sentry/transport/http_transport"
