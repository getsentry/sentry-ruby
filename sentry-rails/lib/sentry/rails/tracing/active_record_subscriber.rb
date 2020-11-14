module Sentry
  module Rails
    module Tracing
      class ActiveRecordSubscriber < AbstractSubscriber
        EVENT_NAME = "sql.active_record".freeze
        EXCLUDED_EVENTS = ["SCHEMA", "TRANSACTION"].freeze

        def self.subscribe!
          subscribe_to_event(EVENT_NAME) do |event_name, duration, payload|
            if !EXCLUDED_EVENTS.include? payload[:name]
              timestamp = Time.now.utc.to_f
              start_timestamp = timestamp - duration.to_f

              new_span = Sentry.get_transaction.start_child(op: event_name, description: payload[:sql], start_timestamp: start_timestamp, timestamp: timestamp)
              new_span.set_data(:name, payload[:name])
              new_span.set_data(:connection_id, payload[:connection_id])
            end
          end
        end
      end
    end
  end
end
