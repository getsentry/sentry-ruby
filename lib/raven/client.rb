require 'openssl'
require 'multi_json'

require 'raven/version'
require 'raven/transports/http'
require 'raven/transports/udp'

module Raven

  class Client

    PROTOCOL_VERSION = '2.0'
    USER_AGENT = "raven-ruby/#{Raven::VERSION}"
    CONTENT_TYPE = 'application/json'

    attr_accessor :configuration

    def initialize(configuration)
      @configuration = configuration
    end

    def transport
      @transport ||= case self.configuration.scheme
        when 'udp'
          Transport::UDP.new self.configuration
        when 'http', 'https'
          Transport::HTTP.new self.configuration
        else
          raise "Unknown transport scheme '#{self.configuration.scheme}'"
        end
    end

    def generate_signature(timestamp, data)
      OpenSSL::HMAC.hexdigest(OpenSSL::Digest::Digest.new('sha1'), self.configuration[:secret_key], "#{timestamp} #{data}")
    end

    def generate_auth_header(data)
      now = Time.now.to_i.to_s
      fields = {
        'sentry_version' => PROTOCOL_VERSION,
        'sentry_client' => USER_AGENT,
        'sentry_timestamp' => now,
        'sentry_key' => self.configuration[:public_key],
        'sentry_signature' => generate_signature(now, data)
      }
      'Sentry ' + fields.map{|key, value| "#{key}=#{value}"}.join(', ')
    end

    def send(event)
      return unless configuration.send_in_current_environment?

      # Set the project ID correctly
      event.project = self.configuration[:project_id]
      Raven.logger.debug "Sending event #{event.id} to Sentry"
      encoded_data = encode(event)
      self.transport.send(self.generate_auth_header(encoded_data), encoded_data,
                          content_type: CONTENT_TYPE)
    end

  private

    def encode(event)
      MultiJson.encode(event.to_hash)
    end

  end

end
