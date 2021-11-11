require "json"
require "base64"

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

    attr_reader :logger, :rate_limits, :discarded_events, :last_client_report_sent

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
      event_hash = event.to_hash
      item_type = get_item_type(event_hash)

      if is_rate_limited?(item_type)
        log_info("Envelope [#{item_type}] not sent: rate limiting")
        record_lost_event(:ratelimit_backoff, item_type)

        return
      end

      encoded_data = encode(event)

      return nil unless encoded_data

      send_data(encoded_data)

      event
    end

    def is_rate_limited?(item_type)
      # check category-specific limit
      category_delay =
        case item_type
        when "transaction"
          @rate_limits["transaction"]
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

    def encode(event)
      # Convert to hash
      event_payload = event.to_hash

      event_id = event_payload[:event_id] || event_payload["event_id"]
      item_type = get_item_type(event_payload)

      envelope_header = {
        event_id: event_id,
        dsn: @dsn.to_s,
        sdk: Sentry.sdk_meta,
        sent_at: Sentry.utc_now.iso8601
      }

      event_header = { type: item_type, content_type: 'application/json' }

      envelope = <<~ENVELOPE
        #{JSON.generate(envelope_header)}
        #{JSON.generate(event_header)}
        #{JSON.generate(event_payload)}
      ENVELOPE

      client_report = fetch_pending_client_report
      envelope << client_report if client_report

      log_info("Sending envelope [#{item_type}] #{event_id} to Sentry")

      envelope
    end

    def record_lost_event(reason, item_type)
      return unless @send_client_reports
      return unless CLIENT_REPORT_REASONS.include?(reason)

      item_type ||= 'event'
      @discarded_events[[reason, item_type]] += 1
    end

    private

    def get_item_type(event_hash)
      event_hash[:type] || event_hash["type"] || "event"
    end

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

      client_report_item = <<~CLIENT_REPORT_ITEM
        #{JSON.generate(item_header)}
        #{JSON.generate(item_payload)}
      CLIENT_REPORT_ITEM

      @discarded_events = Hash.new(0)
      @last_client_report_sent = Time.now

      client_report_item
    end
  end
end

require "sentry/transport/dummy_transport"
require "sentry/transport/http_transport"
