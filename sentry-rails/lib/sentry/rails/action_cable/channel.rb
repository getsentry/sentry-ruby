# frozen_string_literal: true

require_relative 'exception_reporter'

module Sentry
  module Rails
    module ActionCable
      module Channel
        module Subscriptions
          extend ActiveSupport::Concern

          included do
            set_callback :subscribe, :around, ->(_, block) { sentry_capture(:subscribe, &block) }, prepend: true
            set_callback :unsubscribe, :around, ->(_, block) { sentry_capture(:unsubscribe, &block) }, prepend: true
          end

          private

          def sentry_capture(hook, &block)
            extra_context = { params: params }

            ExceptionReporter.capture(connection.env, transaction_name: "#{self.class.name}##{hook}", extra_context: extra_context, &block)
          end
        end

        module Actions
          private

          def dispatch_action(action, data)
            extra_context = { params: params, data: data }

            ExceptionReporter.capture(connection.env, transaction_name: "#{self.class.name}##{action}", extra_context: extra_context) { super }
          end
        end
      end
    end
  end
end
