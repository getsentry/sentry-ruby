module Sentry
  module Rails
    class RescuedExceptionInterceptor
      def initialize(app)
        @app = app
      end

      def call(env)
        return @app.call(env) unless Sentry.initialized?

        begin
          @app.call(env)
        rescue => e
          request = ActionDispatch::Request.new(env)

          # Rails' ShowExceptions#render_exception will mutate env for the exceptions app
          # so we need to hold a copy of env to report the accurate data (like request's url)
          if request.show_exceptions?
            scope = Sentry.get_current_scope
            scope.set_rack_env(scope.rack_env.dup)
            transaction = scope.transaction_name

            # we also need to make sure the transaction name won't be overridden by the exceptions app
            scope.add_event_processor do |event, hint|
              event.transaction = transaction
              event
            end
          end

          env["sentry.rescued_exception"] = e if Sentry.configuration.rails.report_rescued_exceptions
          raise e
        end
      end
    end
  end
end
