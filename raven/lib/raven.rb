require 'rubygems'
require 'openssl'
require 'socket'
require 'uri'
require 'uuidtools'
require 'yajl'
require 'faraday'

require 'raven/version'

module Raven

  class Error < Exception
  end

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
        builder.response :logger
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
      self.conn.post do |req|
        req.url '/api/store/'
        req.headers['Content-Type'] = 'application/json'
        req.body = Yajl::Encoder.encode(event.to_hash)
        req.headers[AUTH_HEADER_KEY] = self.generate_auth_header(req.body)
      end
    end

  end

  class Event

    attr_reader :id
    attr_accessor :project, :message, :timestamp, :level
    attr_accessor :logger, :culprit, :server_name, :modules, :extra

    def initialize(options={}, &block)
      @id = UUIDTools::UUID.random_create.hexdigest

      @message = options[:message]
      raise Error.new('A message is required for all events') unless @message && !@message.empty?

      @timestamp = options[:timestamp] || Time.now.utc
      @timestamp = @timestamp.strftime('%Y-%m-%dT%H:%M:%S') if @timestamp.is_a?(Time)
      raise Error.new('A timestamp is required for all events') unless @timestamp

      @level = options[:level]
      raise Error.new('A level is required for all events') unless @level && !@level.empty?

      @logger = options[:logger] || 'root'
      @culprit = options[:culprit]
      #@server_name = options[:server_name] || Socket.gethostbyname(Socket.gethostname).first
      #@modules = options[:modules] || Gem::Specification.each.map{|spec| [spec.name, spec.version]}
      @extra = options[:extra]

      block.call(self) if block
    end

    def to_hash
      data = {
        'event_id' => self.id,
        'message' => self.message,
        'timestamp' => self.timestamp,
        'level' => self.level,
        'project' => self.project,
        'logger' => self.logger,
      }
      data['culprit'] = self.culprit if self.culprit
      data['server_name'] = self.server_name if self.server_name
      data['modules'] = self.modules if self.modules
      data['extra'] = self.extra if self.extra
      data
    end

  end

end
