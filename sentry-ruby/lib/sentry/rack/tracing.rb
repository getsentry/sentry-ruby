module Sentry
  module Rack
    class Tracing
      def initialize(app)
        @app = app
      end

      def call(env)
        Sentry.clone_hub_to_current_thread unless Sentry.get_current_hub

        if Sentry.configuration.traces_sample_rate.to_f == 0.0
          return @app.call(env)
        end

        Sentry.with_scope do |scope|
          scope.set_transaction_name(env["PATH_INFO"]) if env["PATH_INFO"]
          span = Sentry.start_transaction(name: scope.transaction_name, op: "rack.request")
          scope.set_span(span)

          begin
            response = @app.call(env)
          rescue
            finish_span(span, 500)
            raise
          end

          finish_span(span, response[0])
          response
        end
      end

      def finish_span(span, status_code)
        span.set_http_status(status_code)
        span.finish
      end
    end
  end
end
