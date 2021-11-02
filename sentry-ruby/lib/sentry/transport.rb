require "json"
require "base64"

module Sentry
  class Transport
    PROTOCOL_VERSION = '7'
    USER_AGENT = "sentry-ruby/#{Sentry::VERSION}"

    include LoggingHelper

    attr_accessor :configuration
    attr_reader :logger, :rate_limits

    def initialize(configuration)
      @configuration = configuration
      @logger = configuration.logger
      @transport_configuration = configuration.transport
      @dsn = configuration.dsn
      @rate_limits = {}
      @discarded_events = Hash.new(0)
    end

    def send_data(data, options = {})
      raise NotImplementedError
    end

    def send_event(event)
      event_hash = event.to_hash
      item_type = get_item_type(event_hash)
      data_category = get_data_category(item_type)

      unless configuration.sending_allowed?
        log_debug("Envelope [#{item_type}] not sent: #{configuration.error_messages}")

        return
      end

      if is_rate_limited?(data_category)
        log_info("Envelope [#{item_type}] not sent: rate limiting")
        record_lost_event(:ratelimit_backoff, data_category)

        return
      end

      encoded_data = encode(event)

      return nil unless encoded_data

      send_data(encoded_data)

      event
    end

    def is_rate_limited?(data_category)
      # check category-specific limit
      category_delay = @rate_limits[data_category]

      # check universal limit if not category limit
      universal_delay = @rate_limits[nil]

      delay = [category_delay, universal_delay].compact.max

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
      item_type = get_item_type(event_hash)

      envelope = <<~ENVELOPE
        {"event_id":"#{event_id}","dsn":"#{configuration.dsn.to_s}","sdk":#{Sentry.sdk_meta.to_json},"sent_at":"#{Sentry.utc_now.iso8601}"}
        {"type":"#{item_type}","content_type":"application/json"}
        #{JSON.generate(event_hash)}
      ENVELOPE

      log_info("Sending envelope [#{item_type}] #{event_id} to Sentry")

      envelope
    end

    # valid reasons are
    # :ratelimit_backoff
    # :queue_overflow
    # :cache_overflow
    # :network_error
    # :sample_rate
    def record_lost_event(reason, data_category)
      return unless configuration.send_client_reports
      @discarded_events[[reason, data_category]] += 1
    end

    private

    def get_item_type(event_hash)
      event_hash[:type] || event_hash["type"] || "event"
    end

    def get_data_category(item_type)
      item_type == 'transaction' ? 'transaction' : 'error'
    end
  end
end

require "sentry/transport/dummy_transport"
require "sentry/transport/http_transport"
