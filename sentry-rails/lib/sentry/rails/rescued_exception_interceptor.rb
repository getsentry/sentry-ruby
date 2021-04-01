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
            copied_env = scope.rack_env.dup
            copied_env["sentry.original_transaction"] = scope.transaction_name
            scope.set_rack_env(copied_env)

            if report_rescued_exceptions?
              Sentry::Rails.capture_exception(e)
              env["sentry.already_captured"] = true
            end
          end

          env["sentry.rescued_exception"] = e if report_rescued_exceptions?
          raise e
        end
      end

      def report_rescued_exceptions?
        Sentry.configuration.rails.report_rescued_exceptions
      end
    end
  end
end
