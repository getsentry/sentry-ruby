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
          scope.set_span(transaction)

          begin
            response = @app.call(env)
          rescue Sentry::Error
            finish_transaction(transaction, 500)
            raise # Don't capture Sentry errors
          rescue Exception => e
            capture_exception(e)
            finish_transaction(transaction, 500)
            raise
          end

          exception = collect_exception(env)
          capture_exception(exception) if exception

          finish_transaction(transaction, response[0])

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
        sentry_trace = env["HTTP_SENTRY_TRACE"]
        transaction = Sentry::Transaction.from_sentry_trace(sentry_trace, name: scope.transaction_name, op: transaction_op) if sentry_trace
        tr = transaction || Sentry.start_transaction(name: scope.transaction_name, op: transaction_op)
        tr.manual_exclude(env['HTTP_HOST'], env["PATH_INFO"]) if env["PATH_INFO"]
        tr
      end


      def finish_transaction(transaction, status_code)
        transaction.set_http_status(status_code)
        transaction.finish
      end
    end
  end
end
