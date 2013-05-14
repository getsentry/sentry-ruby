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
    def self.capture_exception(exception, env, options = {})
      Raven.capture_exception(exception, options) do |evt|
        evt.interface :http do |int|
          int.from_rack(env)
        end
      end
    end

    def self.capture_message(message, env, options = {})
      Raven.capture_message(message, options) do |evt|
        evt.interface :http do |int|
          int.from_rack(env)
        end
      end
    end

    def initialize(app)
      @app = app
    end

    def call(env)
      # store the current environment in our local context for arbitrary
      # callers
      Raven.rack_context(env)

      begin
        response = @app.call(env)
      rescue Error => e
        raise # Don't capture Raven errors
      rescue Exception => e
        Raven::Rack.capture_exception(e, env)
        raise
      ensure
        Context.clear!
      end

      error = env['rack.exception'] || env['sinatra.error']

      if error
        Raven::Rack.capture_exception(error, env)
      end

      response
    end
  end
end
