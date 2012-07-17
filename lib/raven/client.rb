require 'openssl'
require 'uri'
require 'multi_json'
require 'faraday'

require 'raven/version'
require 'raven/error'

module Raven

  class Client

    PROTOCOL_VERSION = '2.0'
    USER_AGENT = "raven-ruby/#{Raven::VERSION}"
    AUTH_HEADER_KEY = 'X-Sentry-Auth'

    attr_accessor :configuration

    def initialize(configuration)
      @configuration = configuration
    end

    def conn
      # Error checking
      raise Error.new('No server specified') unless self.configuration[:server]
      raise Error.new('No public key specified') unless self.configuration[:public_key]
      raise Error.new('No secret key specified') unless self.configuration[:secret_key]
      raise Error.new('No project ID specified') unless self.configuration[:project_id]

      Raven.logger.debug "Raven client connecting to #{self.configuration[:server]}"

      @conn ||=  Faraday.new(:url => self.configuration[:server]) do |builder|
        builder.adapter  Faraday.default_adapter
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
      response = self.conn.post '/api/store/' do |req|
        req.headers['Content-Type'] = 'application/json'
        req.body = MultiJson.encode(event.to_hash)
        req.headers[AUTH_HEADER_KEY] = self.generate_auth_header(req.body)
      end
      raise Error.new("Error from Sentry server (#{response.status}): #{response.body}") unless response.status == 200
      response
    end

  end

end
