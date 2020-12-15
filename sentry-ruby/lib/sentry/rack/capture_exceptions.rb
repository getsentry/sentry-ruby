module Sentry
  module Rack
    class CaptureExceptions
      def initialize(app)
        @app = app
      end

      def call(env)
        # make sure the current thread has a clean hub
        Sentry.clone_hub_to_current_thread

        Sentry.with_scope do |scope|
          scope.clear_breadcrumbs
          scope.set_transaction_name(env["PATH_INFO"]) if env["PATH_INFO"]
          scope.set_rack_env(env)

          span = Sentry.start_transaction(name: scope.transaction_name, op: "rack.request")
          scope.set_span(span)

          begin
            response = @app.call(env)
          rescue Sentry::Error
            finish_span(span, 500)
            raise # Don't capture Sentry errors
          rescue Exception => e
            Sentry.capture_exception(e)
            finish_span(span, 500)
            raise
          end

          exception = collect_exception(env)
          Sentry.capture_exception(exception) if exception

          finish_span(span, response[0])

          response
        end
      end

      private

      def collect_exception(env)
        env['rack.exception'] || env['sinatra.error']
      end

      def finish_span(span, status_code)
        span.set_http_status(status_code)
        span.finish
      end
    end
  end
end
