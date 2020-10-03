module Sentry
  module Rack
    class CaptureException
      def initialize(app)
        @app = app
      end

      def call(env)
        Sentry.with_scope do
          # store the current environment in our local context for arbitrary
          # callers
          env['sentry.requested_at'] = Time.now
          # Sentry.rack_context(env)
          Sentry.get_current_scope.set_transaction(env["PATH_INFO"]) if env["PATH_INFO"]

          begin
            response = @app.call(env)
          rescue Sentry::Error
            raise # Don't capture Sentry errors
          rescue Exception => e
            capture_exception(e, env)
            raise
          end

          error = env['rack.exception'] || env['sinatra.error']
          capture_exception(error, env) if error

          response
        end
      end

      def capture_exception(exception, env, **options)
        if requested_at = env['sentry.requested_at']
          options[:time_spent] = Time.now - requested_at
        end

        Sentry.capture_exception(exception, **options) do |evt|
          evt.interface :http do |int|
            int.from_rack(env)
          end
        end
      end
    end
  end
end
