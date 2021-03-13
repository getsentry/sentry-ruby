require "json"
require "base64"

module Sentry
  class Transport
    PROTOCOL_VERSION = '5'
    USER_AGENT = "sentry-ruby/#{Sentry::VERSION}"

    include LoggingHelper

    attr_accessor :configuration
    attr_reader :logger

    def initialize(configuration)
      @configuration = configuration
      @logger = configuration.logger
      @transport_configuration = configuration.transport
      @dsn = configuration.dsn
      @rate_limits = {}
    end

    def send_data(data, options = {})
      raise NotImplementedError
    end

    def send_event(event)
      unless configuration.sending_allowed?
        log_debug("Event not sent: #{configuration.error_messages}")
        return
      end

      return if is_rate_limited?(event)

      encoded_data = encode(event)

      return nil unless encoded_data

      send_data(encoded_data)

      event
    end

    def is_rate_limited?(event)
      event_hash = event.to_hash
      event_type = event_hash[:type] || event_hash['type']

      # check category-specific limit
      delay =
        case event_type
        when "event"
          # confusing mapping, but it's decided by Sentry
          @rate_limits["error"]
        when "transaction"
          @rate_limits["transaction"]
        end

      # check universal limit if not category limit
      delay ||= @rate_limits[nil]

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
      event_hash = event.to_hash

      event_id = event_hash[:event_id] || event_hash["event_id"]
      item_type = event_hash[:type] || event_hash["type"] || "event"

      envelope = <<~ENVELOPE
        {"event_id":"#{event_id}","dsn":"#{configuration.dsn.to_s}","sdk":#{Sentry.sdk_meta.to_json},"sent_at":"#{Sentry.utc_now.iso8601}"}
        {"type":"#{item_type}","content_type":"application/json"}
        #{JSON.generate(event_hash)}
      ENVELOPE

      log_info("Sending envelope [#{item_type}] #{event_id} to Sentry")

      envelope
    end
  end
end

require "sentry/transport/dummy_transport"
require "sentry/transport/http_transport"
