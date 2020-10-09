require "json"
require "base64"
require "sentry/transport/state"

module Sentry
  class Transport
    PROTOCOL_VERSION = '5'
    USER_AGENT = "sentry-ruby/#{Sentry::VERSION}"
    CONTENT_TYPE = 'application/json'

    attr_accessor :configuration, :state

    def initialize(configuration)
      @configuration = configuration
      @state = State.new
    end

    def send_data(data, options = {})
      raise NotImplementedError
    end

    def send_event(event)
      content_type, encoded_data = prepare_encoded_event(event)

      return nil unless encoded_data

      begin
        if configuration.async?
          begin
            # We have to convert to a JSON-like hash, because background job
            # processors (esp ActiveJob) may not like weird types in the event hash
            configuration.async.call(event.to_json_compatible)
          rescue => e
            configuration.logger.error("async event sending failed: #{e.message}")
            send_data(encoded_data, content_type: content_type)
          end
        else
          send_data(encoded_data, content_type: content_type)
        end

        state.success
      rescue => e
        failed_for_exception(e, event)
        return
      end

      event
    end

    def generate_auth_header
      now = Time.now.to_i.to_s
      fields = {
        'sentry_version' => PROTOCOL_VERSION,
        'sentry_client' => USER_AGENT,
        'sentry_timestamp' => now,
        'sentry_key' => configuration.dsn.public_key
      }
      fields['sentry_secret'] = configuration.dsn.secret_key if configuration.dsn.secret_key
      'Sentry ' + fields.map { |key, value| "#{key}=#{value}" }.join(', ')
    end

    private

    def prepare_encoded_event(event)
      # Convert to hash
      event_hash = event.to_hash

      unless @state.should_try?
        failed_for_previous_failure(event_hash)
        return
      end

      event_id = event_hash[:event_id] || event_hash['event_id']
      configuration.logger.info "Sending event #{event_id} to Sentry"
      encode(event_hash)
    end

    def encode(event)
      encoded = JSON.fast_generate(event.to_hash)

      case configuration.encoding
      when 'gzip'
        ['application/octet-stream', Base64.strict_encode64(Zlib::Deflate.deflate(encoded))]
      else
        ['application/json', encoded]
      end
    end

    def failed_for_exception(e, event)
      @state.failure
      configuration.logger.warn "Unable to record event with remote Sentry server (#{e.class} - #{e.message}):\n#{e.backtrace[0..10].join("\n")}"
      log_not_sending(event)
    end

    def failed_for_previous_failure(event)
      configuration.logger.warn "Not sending event due to previous failure(s)."
      log_not_sending(event)
    end

    def log_not_sending(event)
      configuration.logger.warn("Failed to submit event: #{Event.get_log_message(event.to_hash)}")
    end
  end
end

require "sentry/transport/dummy_transport"
require "sentry/transport/http_transport"
require "sentry/transport/stdout_transport"
