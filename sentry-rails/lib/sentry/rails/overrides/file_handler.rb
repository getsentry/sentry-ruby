module Sentry
  module Rails
    module Overrides
      module FileHandler
        def serve(*args)
          if Sentry.initialized? && current_transaction = Sentry.get_current_scope.span
            # we don't want to expose a setter for @sampled just for this case
            current_transaction.instance_variable_set(:@sampled, false)
          end

          super
        end
      end
    end
  end
end
