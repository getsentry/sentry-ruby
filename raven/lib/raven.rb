require 'uri'
require 'uuidtools'

module Raven

  class Error < Exception
  end

  class Client

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
        options[:server] << ":#{uri.port}" unless uri.port == {"http"=>80,"https"=>443}[uri.scheme]
        options[:server] << uri_path.join('/')
        options[:public_key] = uri.user
        options[:secret_key] = uri.password
      end
      @server = options[:server]
      @public_key = options[:public_key]
      @secret_key = options[:secret_key]
      @project_id = options[:project_id]
    end

  end

  class Event

    attr_reader :id
    attr_accessor :message, :timestamp, :level

    def initialize(options={}, &block)
      @id = UUIDTools::UUID.random_create.hexdigest

      @message = options[:message]
      raise Error.new('A message is required for all events') unless @message && !@message.empty?

      @timestamp = options[:timestamp] || Time.now.utc
      @timestamp = @timestamp.strftime('%Y-%m-%dT%H:%M:%S') if @timestamp.is_a?(Time)
      raise Error.new('A timestamp is required for all events') unless @timestamp

      @level = options[:level]
      raise Error.new('A level is required for all events') unless @level && !@level.empty?

      block.call(self) if block
    end

  end

end
