module Sentry
  module Rails
    module ControllerTransaction
      def self.included(base)
        base.prepend_around_action do |controller, block|
          Sentry.get_current_scope.set_transaction_name("#{controller.class}##{controller.action_name}")
          block.call
          Sentry.get_current_scope.transaction_names.pop
        end
      end
    end
  end
end
