module Sentry
  module Rails
    module Tracing
      class ActionViewSubscriber < AbstractSubscriber
        EVENT_NAMES = ["render_template.action_view", "render_partial.action_view", "render_collection.action_view"]

        def self.subscribe!
          EVENT_NAMES.each do |event_name|
            subscribe_to_event(event_name) do |event_name, duration, payload|
              record_on_current_span(op: event_name, start_timestamp: payload[:start_timestamp], description: payload[:identifier], duration: duration)
            end
          end
        end

        def self.unsubscribe!
          EVENT_NAMES.each do |event_name|
            ActiveSupport::Notifications.unsubscribe(event_name)
          end
        end
      end
    end
  end
end
