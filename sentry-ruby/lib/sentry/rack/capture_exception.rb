module Sentry
  module Rack
    class CaptureException
      def initialize(app)
        @app = app
      end

      def call(env)
        # this call clones the main (global) hub
        # and assigns it to the current thread's Sentry#get_current_hub
        # it's essential for multi-thread servers (e.g. puma)
        Sentry.clone_hub_to_current_thread unless Sentry.get_current_hub
        # this call creates an isolated scope for every request
        # it's essential for multi-process servers (e.g. unicorn)
        Sentry.with_scope do |scope|
          env['sentry.requested_at'] = Time.now
          env['sentry.client'] = Sentry.get_current_client

          scope.set_transaction_name(env["PATH_INFO"]) if env["PATH_INFO"]
          scope.set_rack_env(env)

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
