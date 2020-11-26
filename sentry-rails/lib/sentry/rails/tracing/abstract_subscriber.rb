module Sentry
  module Rails
    module Tracing
      class AbstractSubscriber

        class << self
          def subscribe!
            raise NotImplementedError
          end

          def unsubscribe!
            ActiveSupport::Notifications.unsubscribe(self::EVENT_NAME)
          end

          def subscribe_to_event(event_name)
            if ::Rails.version.to_i == 5
              ActiveSupport::Notifications.subscribe(event_name) do |_, start, finish, _, payload|
                next unless Tracing.get_current_transaction

                duration = finish.to_f - start.to_f
                yield(event_name, duration, payload)
              end
            else
              ActiveSupport::Notifications.subscribe(event_name) do |event|
                next unless Tracing.get_current_transaction

                yield(event_name, event.duration, event.payload)
              end
            end
          end

          def record_on_current_span(duration:, **options)
            return unless options[:start_timestamp]

            scope = Sentry.get_current_scope
            transaction = scope.get_transaction
            return unless transaction

            span = transaction.start_child(**options)
            # duration in ActiveSupport is computed in millisecond
            # so we need to covert it as second before calculating the timestamp
            span.set_timestamp(span.start_timestamp + duration / 1000)
            yield(span) if block_given?
          end
        end
      end
    end
  end
end
