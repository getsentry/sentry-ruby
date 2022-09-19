module Sentry
  module Rails
    module ControllerTransaction
      def self.included(base)
        base.prepend_before_action do |controller|
          Sentry.get_current_scope.set_transaction_name("#{controller.class}##{controller.action_name}", source: :view)
        end
      end
    end
  end
end
