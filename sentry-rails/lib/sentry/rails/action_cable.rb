module Sentry
  module Rails
    module ActionCableExtensions
      class ErrorHandler
        class << self
          def capture(env, transaction_name:, extra_context: nil, &block)
            Sentry.with_scope do |scope|
              scope.set_rack_env(env)
              scope.set_extras(action_cable: extra_context) if extra_context
              scope.set_transaction_name(transaction_name)
              transaction = start_transaction(env, scope.transaction_name)
              scope.set_span(transaction) if transaction

              begin
                block.call
                finish_transaction(transaction, 200)
              rescue Exception => e # rubocop:disable Lint/RescueException
                Sentry::Rails.capture_exception(e)
                finish_transaction(transaction, 500)

                raise
              end
            end
          end

          def start_transaction(env, transaction_name)
            sentry_trace = env["HTTP_SENTRY_TRACE"]
            options = { name: transaction_name, op: "rails.action_cable".freeze }
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

      module Connection
        private

        def handle_open
          ErrorHandler.capture(env, transaction_name: "#{self.class.name}#connect") do
            super
          end
        end

        def handle_close
          ErrorHandler.capture(env, transaction_name: "#{self.class.name}#disconnect") do
            super
          end
        end
      end

      module Channel
        module Subscriptions
          def self.included(base)
            base.class_eval do
              set_callback :subscribe, :around, ->(_, block) { sentry_capture(:subscribed, &block) }, prepend: true
              set_callback :unsubscribe, :around, ->(_, block) { sentry_capture(:unsubscribed, &block) }, prepend: true
            end
          end

          private

          def sentry_capture(hook, &block)
            extra_context = { params: params }

            ErrorHandler.capture(connection.env, transaction_name: "#{self.class.name}##{hook}", extra_context: extra_context, &block)
          end
        end

        module Actions
          private

          def dispatch_action(action, data)
            extra_context = { params: params, data: data }

            ErrorHandler.capture(connection.env, transaction_name: "#{self.class.name}##{action}", extra_context: extra_context) do
              super
            end
          end
        end
      end
    end
  end
end
