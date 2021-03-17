require "sentry/rails/tracing/abstract_subscriber"

module Sentry
  module Rails
    module Tracing
      class ActionViewSubscriber < AbstractSubscriber
        EVENT_NAME = "render_template.action_view".freeze

        def self.subscribe!
          subscribe_to_event(EVENT_NAME) do |event_name, duration, payload|
            record_on_current_span(op: event_name, start_timestamp: payload[:start_timestamp], description: payload[:identifier], duration: duration)
          end
        end
      end
    end
  end
end
