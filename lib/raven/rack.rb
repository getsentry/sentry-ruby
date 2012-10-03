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
    def initialize(app)
      @app = app
    end

    def call(env)
      begin
        response = @app.call(env)
      rescue Error => e
        raise # Don't capture Raven errors
      rescue Exception => e
        evt = Event.capture_rack_exception(e, env)
        Raven.send(evt)
        raise
      end

      if env['rack.exception']
        evt = Event.capture_rack_exception(env['rack.exception'], env)
        Raven.send(evt) if evt
      end

      response
    end
  end
end
