module Raven
  class Rails
    module ControllerTransaction
      def self.included(base)
        base.class_eval do
          around_action do |controller|
            Raven.context.transaction.push "#{controller.class}##{controller.action_name}"
            yield
            Raven.context.transaction.pop
          end
        end
      end
    end
  end
end
