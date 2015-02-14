require 'time'
require 'rack'

module Raven
  # Middleware for Rack applications. Any errors raised by the upstream
  # application will be delivered to Sentry and re-raised.
  #
  # Synopsis:
  #
  #   require 'rack'
  #   require 'raven'
  #
  #   Raven.configure do |config|
  #     config.server = 'http://my_dsn'
  #   end
  #
  #   app = Rack::Builder.app do
  #     use Raven::Rack
  #     run lambda { |env| raise "Rack down" }
  #   end
  #
  # Use a standard Raven.configure call to configure your server credentials.
  class Rack

    def self.capture_type(exception, env, options = {})
      if env['requested_at']
        options[:time_spent] = Time.now - env['requested_at']
      end
      Raven.capture_type(exception, options) do |evt|
        evt.interface :http do |int|
          int.from_rack(env)
        end
      end
    end
    class << self
      alias_method :capture_message, :capture_type
      alias_method :capture_exception, :capture_type
    end

    def initialize(app)
      @app = app
    end

    def call(env)
      # clear context at the beginning of the request to ensure a clean slate
      Context.clear!

      # store the current environment in our local context for arbitrary
      # callers
      env['requested_at'] = Time.now
      Raven.rack_context(env)

      begin
        response = @app.call(env)
      rescue Error
        raise # Don't capture Raven errors
      rescue Exception => e
        Raven.logger.debug "Collecting %p: %s" % [ e.class, e.message ]
        Raven::Rack.capture_exception(e, env)
        raise
      end

      error = env['rack.exception'] || env['sinatra.error']

      Raven::Rack.capture_exception(error, env) if error

      response
    end
  end
end

module Raven
  module InterfaceFromRack
    CGI_VARIABLES = Set.new(%W[
        AUTH_TYPE
        CONTENT_LENGTH
        CONTENT_TYPE
        GATEWAY_INTERFACE
        HTTPS
        PATH_INFO
        PATH_TRANSLATED
        QUERY_STRING
        REMOTE_ADDR
        REMOTE_HOST
        REMOTE_IDENT
        REMOTE_USER
        REQUEST_METHOD
        SCRIPT_NAME
        SERVER_NAME
        SERVER_PORT
        SERVER_PROTOCOL
        SERVER_SOFTWARE
      ]).freeze

    def from_rack(rack_env)
      set_headers_and_env(rack_env)
      set_request_data(rack_env)
    end

    def set_request_data(rack_env)
      req = ::Rack::Request.new(rack_env)
      self.url = req.scheme && req.url.split('?').first
      self.method = req.request_method
      self.query_string = req.query_string
      self.data = req.form_data? ? req.POST : req.body && req.body.string
    end

    def set_headers_and_env(rack_env)
      rack_env = Hash[rack_env.map{ |k, v| [k.to_s, v.to_s] }.select { |ary| ary[0].upcase == ary[0] }]
      rack_env.each_pair do |key, value|
        if key.start_with?('HTTP_')
          # Header
          http_key = key[5..key.length - 1].split('_').map { |s| s.capitalize }.join('-')
          self.headers[http_key] = value
        elsif CGI_VARIABLES.include? key
          # Environment
          self.env[key] = value
        end
      end
    end
  end
end

module Raven
  class HttpInterface
    include InterfaceFromRack
  end
end
