require "sentry/rails/tracing/abstract_subscriber"
require "sentry/rails/instrument_payload_cleanup_helper"

module Sentry
  module Rails
    module Tracing
      class ActionControllerSubscriber < AbstractSubscriber
        extend InstrumentPayloadCleanupHelper

        EVENT_NAMES = ["process_action.action_controller"].freeze

        def self.subscribe!
          subscribe_to_event(EVENT_NAMES) do |event_name, duration, payload|
            controller = payload[:controller]
            action = payload[:action]

            record_on_current_span(
              op: event_name,
              start_timestamp: payload[START_TIMESTAMP_NAME],
              description: "#{controller}##{action}",
              duration: duration
            ) do |span|
              payload = payload.dup
              cleanup_data(payload)
              span.set_data(:payload, payload)
              span.set_http_status(payload[:status])
            end
          end
        end
      end
    end
  end
end
