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

          transaction = start_transaction(env, scope)
          transaction ? scope.set_span(transaction) : nil

          begin
            response = @app.call(env)
          rescue Sentry::Error
            transaction ? finish_transaction(transaction, 500) : nil
            raise # Don't capture Sentry errors
          rescue Exception => e
            capture_exception(e)
            transaction ? finish_transaction(transaction, 500) : nil
            raise
          end

          exception = collect_exception(env)
          capture_exception(exception) if exception

          transaction ? finish_transaction(transaction, response[0]) : nil

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

      def start_transaction(env, scope)
        return unless Sentry.configuration.tracing_enabled?

        sentry_trace = env["HTTP_SENTRY_TRACE"]
        options = {name: scope.transaction_name, op: transaction_op}

        # if tracing is disabled, these will both return nil
        transaction = Sentry::Transaction.from_sentry_trace(sentry_trace, **options) if sentry_trace
        Sentry.start_transaction(transaction: transaction, **options)
      end


      def finish_transaction(transaction, status_code)
        return unless transaction

        transaction.set_http_status(status_code)
        transaction.finish
      end
    end
  end
end
