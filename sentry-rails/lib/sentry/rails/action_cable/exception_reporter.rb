# frozen_string_literal: true

module Sentry
  module Rails
    module ActionCable
      class ExceptionReporter
        TRANSACTION_PREFIX = 'ActionCable'

        def self.capture(env, transaction_name:, extra_context: nil, &block)
          Sentry.with_scope do |scope|
            scope.set_rack_env(env)
            scope.set_extras(action_cable: extra_context) if extra_context

            scope.set_transaction_name [TRANSACTION_PREFIX, transaction_name].join('/')

            begin
              block.call
            rescue Exception => e # rubocop:disable Lint/RescueException
              Sentry.capture_exception(e)

              raise
            end
          end
        end
      end
    end
  end
end
