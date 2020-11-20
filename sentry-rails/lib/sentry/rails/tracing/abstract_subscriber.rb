module Sentry
  module Rails
    module Tracing
      class AbstractSubscriber

        class << self
          def subscribe!
            raise NotImplementedError
          end

          def subscribe_to_event(event_name)
            if ::Rails.version.to_i == 5
              ActiveSupport::Notifications.subscribe(event_name) do |_, start, finish, _, payload|
                next unless get_current_transaction

                duration = finish.to_f - start.to_f
                yield(event_name, duration, payload)
              end
            else
              ActiveSupport::Notifications.subscribe(event_name) do |event|
                next unless get_current_transaction

                yield(event_name, event.duration, event.payload)
              end
            end
          end

          def get_current_transaction
            Sentry.get_current_scope.get_transaction
          end
        end
      end
    end
  end
end
