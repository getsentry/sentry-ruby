module Sentry
  module Rails
    module Tracing
      class ActiveRecordSubscriber < AbstractSubscriber
        EVENT_NAME = "sql.active_record".freeze
        EXCLUDED_EVENTS = ["SCHEMA", "TRANSACTION"].freeze

        def self.subscribe!
          subscribe_to_event(EVENT_NAME) do |event_name, duration, payload|
            next if EXCLUDED_EVENTS.include? payload[:name]

            record_on_current_span(op: event_name, start_timestamp: payload[:start_timestamp], duration: duration) do |span|
              span.set_description(payload[:sql])
              span.set_data(:connection_id, payload[:connection_id])
            end
          end
        end
      end
    end
  end
end
