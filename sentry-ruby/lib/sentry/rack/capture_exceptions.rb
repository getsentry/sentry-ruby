module Sentry
  module Rack
    class CaptureExceptions
      def initialize(app)
        @app = app
      end

      def call(env)
        return @app.call(env) unless Sentry.initialized?

        # make sure the current thread has a clean hub
        Sentry.clone_hub_to_current_thread

        Sentry.with_scope do |scope|
          scope.clear_breadcrumbs
          scope.set_transaction_name(env["PATH_INFO"]) if env["PATH_INFO"]
          scope.set_rack_env(env)

          span =
            if sentry_trace = env["sentry-trace"]
              Sentry::Transaction.from_sentry_trace(sentry_trace, name: scope.transaction_name, op: transaction_op)
            else
              Sentry.start_transaction(name: scope.transaction_name, op: transaction_op)
            end

          scope.set_span(span)

          begin
            response = @app.call(env)
          rescue Sentry::Error
            finish_span(span, 500)
            raise # Don't capture Sentry errors
          rescue Exception => e
            capture_exception(e)
            finish_span(span, 500)
            raise
          end

          exception = collect_exception(env)
          capture_exception(exception) if exception

          finish_span(span, response[0])

          response
        end
      end

      private

      def collect_exception(env)
        env['rack.exception'] || env['sinatra.error']
      end

      def transaction_op
        "rack.request".freeze
      end

      def capture_exception(exception)
        Sentry.capture_exception(exception)
      end

      def finish_span(span, status_code)
        span.set_http_status(status_code)
        span.finish
      end
    end
  end
end
