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
          # there could be some breadcrumbs already stored in the top-level scope
          # and for request information, we don't need those breadcrumbs
          scope.clear_breadcrumbs
          env['sentry.client'] = Sentry.get_current_client

          scope.set_transaction_name(env["PATH_INFO"]) if env["PATH_INFO"]
          scope.set_rack_env(env)

          begin
            response = @app.call(env)
          rescue Sentry::Error
            raise # Don't capture Sentry errors
          rescue Exception => e
            Sentry.capture_exception(e)
            raise
          end

          exception = collect_exception(env)
          Sentry.capture_exception(exception) if exception

          response
        end
      end

      def collect_exception(env)
        env['rack.exception'] || env['sinatra.error']
      end
    end
  end
end
