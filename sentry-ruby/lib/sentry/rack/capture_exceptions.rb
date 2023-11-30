# frozen_string_literal: true

module Sentry
  module Rack
    class CaptureExceptions
      ERROR_EVENT_ID_KEY = "sentry.error_event_id"
      IGNORED_HTTP_METHODS = ["HEAD", "OPTIONS"].freeze

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
            scope.set_transaction_name(env["PATH_INFO"], source: :url) if env["PATH_INFO"]
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
        "http.server".freeze
      end

      def capture_exception(exception, env)
        Sentry.capture_exception(exception).tap do |event|
          env[ERROR_EVENT_ID_KEY] = event.event_id if event
        end
      end

      def start_transaction(env, scope)
        # Tell Sentry to not sample this transaction if this is an HTTP OPTIONS or HEAD request.
        # Return early to avoid extra work that's not useful anyway, because this
        # transaction won't be sampled.
        # If we return nil here, it'll be passed to `finish_transaction` later, which is safe.
        return nil if IGNORED_HTTP_METHODS.include?(env["REQUEST_METHOD"])
                
        options = {
          name: scope.transaction_name,
          source: scope.transaction_source, 
          op: transaction_op
        }

        transaction = Sentry.continue_trace(env, **options)
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
