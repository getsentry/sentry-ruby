module Raven
  class Rails
    module ControllerTransaction
      def self.included(base)
        base.prepend_around_action do |controller, block|
          Raven.context.transaction.push "#{controller.class}##{controller.action_name}"
          block.call
          Raven.context.transaction.pop
        end
      end
    end
  end
end
