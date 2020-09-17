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
      if env['raven.requested_at']
        options[:time_spent] = Time.now - env['raven.requested_at']
      end
      Raven.capture_type(exception, options) do |evt|
        evt.interface :http do |int|
          int.from_rack(env)
        end
      end
    end
    class << self
      alias capture_message capture_type
      alias capture_exception capture_type
    end

    def initialize(app)
      @app = app
    end

    def call(env)
      # store the current environment in our local context for arbitrary
      # callers
      env['raven.requested_at'] = Time.now
      Raven.rack_context(env)
      Raven.context.transaction.push(env["PATH_INFO"]) if env["PATH_INFO"]

      begin
        response = @app.call(env)
      rescue Error
        raise # Don't capture Raven errors
      rescue Exception => e
        Raven::Rack.capture_exception(e, env)
        raise
      end

      error = env['rack.exception'] || env['sinatra.error']
      Raven::Rack.capture_exception(error, env) if error

      response
    ensure
      Context.clear!
      BreadcrumbBuffer.clear!
    end
  end

  module RackInterface
    def from_rack(env_hash)
      req = ::Rack::Request.new(env_hash)

      self.url = req.scheme && req.url.split('?').first
      self.method = req.request_method
      self.query_string = req.query_string
      self.data = read_data_from(req)
      self.cookies = req.cookies

      self.headers = format_headers_for_sentry(env_hash)
      self.env     = format_env_for_sentry(env_hash)
    end

    private

    # See Sentry server default limits at
    # https://github.com/getsentry/sentry/blob/master/src/sentry/conf/server.py
    def read_data_from(request)
      if request.form_data?
        request.POST
      elsif request.body # JSON requests, etc
        data = request.body.read(4096 * 4) # Sentry server limit
        request.body.rewind
        data
      end
    rescue IOError => e
      e.message
    end

    def format_headers_for_sentry(env_hash)
      env_hash.each_with_object({}) do |(key, value), memo|
        begin
          key = key.to_s # rack env can contain symbols
          value = value.to_s
          next unless key.upcase == key # Non-upper case stuff isn't either

          # Rack adds in an incorrect HTTP_VERSION key, which causes downstream
          # to think this is a Version header. Instead, this is mapped to
          # env['SERVER_PROTOCOL']. But we don't want to ignore a valid header
          # if the request has legitimately sent a Version header themselves.
          # See: https://github.com/rack/rack/blob/028438f/lib/rack/handler/cgi.rb#L29
          next if key == 'HTTP_VERSION' && value == env_hash['SERVER_PROTOCOL']
          next if key == 'HTTP_COOKIE' # Cookies don't go here, they go somewhere else

          next unless key.start_with?('HTTP_') || %w(CONTENT_TYPE CONTENT_LENGTH).include?(key)

          # Rack stores headers as HTTP_WHAT_EVER, we need What-Ever
          key = key.sub(/^HTTP_/, "")
          key = key.split('_').map(&:capitalize).join('-')
          memo[key] = value
        rescue StandardError => e
          # Rails adds objects to the Rack env that can sometimes raise exceptions
          # when `to_s` is called.
          # See: https://github.com/rails/rails/blob/master/actionpack/lib/action_dispatch/middleware/remote_ip.rb#L134
          Raven.logger.warn("Error raised while formatting headers: #{e.message}")
          next
        end
      end
    end

    def format_env_for_sentry(env_hash)
      return env_hash if Raven.configuration.rack_env_whitelist.empty?

      env_hash.select do |k, _v|
        Raven.configuration.rack_env_whitelist.include? k.to_s
      end
    end
  end

  class HttpInterface
    include RackInterface
  end
end
