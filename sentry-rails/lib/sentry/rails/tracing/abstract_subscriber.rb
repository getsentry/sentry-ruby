module Sentry
  module Rails
    module Tracing
      class AbstractSubscriber

        class << self
          def subscribe!
            raise NotImplementedError
          end

          def unsubscribe!
            self::EVENT_NAMES.each do |name|
              ActiveSupport::Notifications.unsubscribe(name)
            end
          end

          if ::Rails.version.to_i == 5
            def subscribe_to_event(event_names)
              event_names.each do |event_name|
                ActiveSupport::Notifications.subscribe(event_name) do |*args|
                  next unless Tracing.get_current_transaction

                  event = ActiveSupport::Notifications::Event.new(*args)
                  yield(event_name, event.duration, event.payload)
                end
              end
            end
          else
            def subscribe_to_event(event_names)
              event_names.each do |event_name|
                ActiveSupport::Notifications.subscribe(event_name) do |event|
                  next unless Tracing.get_current_transaction

                  yield(event_name, event.duration, event.payload)
                end
              end
            end
          end

          def record_on_current_span(duration:, **options)
            return unless options[:start_timestamp]

            scope = Sentry.get_current_scope
            transaction = scope.get_transaction
            return unless transaction && transaction.sampled

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
