module Sentry
  module Rails
    module Tracing
      class AbstractSubscriber

        def self.subscribe!
          raise NotImplementedError
        end

        def self.subscribe_to_event(event_name)
          if ::Rails.version.to_i == 5
            ActiveSupport::Notifications.subscribe(event_name) do |_, start, finish, _, payload|
              next unless Sentry.get_transaction

              duration = finish.to_f - start.to_f
              yield(event_name, duration, payload)
            end
          else
            ActiveSupport::Notifications.subscribe(event_name) do |event|
              next unless Sentry.get_transaction

              yield(event_name, event.duration, event.payload)
            end
          end
        end
      end
    end
  end
end
