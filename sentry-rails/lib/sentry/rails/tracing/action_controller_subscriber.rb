module Sentry
  module Rails
    module Tracing
      class ActionControllerSubscriber < AbstractSubscriber
        EVENT_NAME = "process_action.action_controller".freeze

        def self.subscribe!
          subscribe_to_event(EVENT_NAME) do |event_name, duration, payload|
            record_on_current_span(op: event_name, start_timestamp: payload[:start_timestamp], duration: duration) do |span|
              controller = payload[:controller]
              action = payload[:action]
              description = "#{controller}##{action}"

              span.set_description(description)
              span.set_data(:payload, payload)
              span.set_http_status(payload[:status])
            end
          end
        end
      end
    end
  end
end
