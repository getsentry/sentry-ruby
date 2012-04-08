require 'openssl'
require 'uri'
require 'yajl'
require 'faraday'

require 'raven/version'
require 'raven/error'

module Raven

  class Client

    PROTOCOL_VERSION = '2.0'
    USER_AGENT = "raven-ruby/#{Raven::VERSION}"
    AUTH_HEADER_KEY = 'X-Sentry-Auth'

    attr_reader :server, :public_key, :secret_key, :project_id

    def initialize(dsn, options={})
      if options.empty? && dsn.is_a?(Hash)
        dsn, options = nil, dsn
      end
      dsn ||= options[:dsn]
      dsn ||= ENV['SENTRY_DSN']
      if dsn && !dsn.empty?
        uri = URI::parse(dsn)
        uri_path = uri.path.split('/')
        options[:project_id] = uri_path.pop
        options[:server] = "#{uri.scheme}://#{uri.host}"
        options[:server] << ":#{uri.port}" unless uri.port == {'http'=>80,'https'=>443}[uri.scheme]
        options[:server] << uri_path.join('/')
        options[:public_key] = uri.user
        options[:secret_key] = uri.password
      end
      @server = options[:server]
      @public_key = options[:public_key]
      @secret_key = options[:secret_key]
      @project_id = options[:project_id]
    end

    def conn
      @conn ||=  Faraday.new(:url => self.server) do |builder|
        builder.adapter  :net_http
      end
    end


    def generate_signature(timestamp, data)
      OpenSSL::HMAC.hexdigest(OpenSSL::Digest::Digest.new('sha1'), self.secret_key, "#{timestamp} #{data}")
    end

    def generate_auth_header(data)
      now = Time.now.to_i.to_s
      fields = {
        'sentry_version' => PROTOCOL_VERSION,
        'sentry_client' => USER_AGENT,
        'sentry_timestamp' => now,
        'sentry_key' => self.public_key,
        'sentry_signature' => generate_signature(now, data)
      }
      'Sentry ' + fields.map{|key, value| "#{key}=#{value}"}.join(', ')
    end

    def send(event)
      # Set the project ID correctly
      event.project = self.project_id
      response = self.conn.post '/api/store/' do |req|
        req.headers['Content-Type'] = 'application/json'
        req.body = Yajl::Encoder.encode(event.to_hash)
        req.headers[AUTH_HEADER_KEY] = self.generate_auth_header(req.body)
      end
      raise Error.new("Error from Sentry server (#{response.status_code}): #{response.body}") unless response.status_code == 200
      response
    end

  end

end
