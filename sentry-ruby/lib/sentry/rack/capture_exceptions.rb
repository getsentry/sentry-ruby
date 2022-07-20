# frozen_string_literal: true

module Sentry
  module Rack
    class CaptureExceptions
      ERROR_EVENT_ID_KEY = "sentry.error_event_id"

      def initialize(app)
        @app = app
      end

      def call(env)
        return @app.call(env) unless Sentry.initialized?

        # make sure the current thread has a clean hub
        Sentry.clone_hub_to_current_thread

        Sentry.with_scope do |scope|
          Sentry.with_session_tracking do
            scope.clear_breadcrumbs
            scope.set_transaction_name(env["PATH_INFO"]) if env["PATH_INFO"]
            scope.set_rack_env(env)

            transaction = start_transaction(env, scope)
            scope.set_span(transaction) if transaction

            begin
              response = @app.call(env)
            rescue Sentry::Error
              finish_transaction(transaction, 500)
              raise # Don't capture Sentry errors
            rescue Exception => e
              capture_exception(e, env)
              finish_transaction(transaction, 500)
              raise
            end

            exception = collect_exception(env)
            capture_exception(exception, env) if exception

            finish_transaction(transaction, response[0])

            response
          end
        end
      end

      private

      def collect_exception(env)
        env['rack.exception'] || env['sinatra.error']
      end

      def transaction_op
        "rack.request".freeze
      end

      def capture_exception(exception, env)
        Sentry.capture_exception(exception).tap do |event|
          env[ERROR_EVENT_ID_KEY] = event.event_id if event
        end
      end

      def start_transaction(env, scope)
        sentry_trace = env["HTTP_SENTRY_TRACE"]
        options = { name: scope.transaction_name, op: transaction_op }
        transaction = Sentry::Transaction.from_sentry_trace(sentry_trace, **options) if sentry_trace
        Sentry.start_transaction(transaction: transaction, custom_sampling_context: { env: env }, **options)
      end


      def finish_transaction(transaction, status_code)
        return unless transaction

        transaction.set_http_status(status_code)
        transaction.finish
      end
    end
  end
end
