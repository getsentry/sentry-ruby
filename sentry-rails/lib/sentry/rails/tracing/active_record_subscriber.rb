require "sentry/rails/tracing/abstract_subscriber"

module Sentry
  module Rails
    module Tracing
      class ActiveRecordSubscriber < AbstractSubscriber
        EVENT_NAMES = ["sql.active_record"].freeze
        SPAN_PREFIX = "db.".freeze
        EXCLUDED_EVENTS = ["SCHEMA", "TRANSACTION"].freeze

        def self.subscribe!
          subscribe_to_event(EVENT_NAMES) do |event_name, duration, payload|
            next if EXCLUDED_EVENTS.include? payload[:name]

            record_on_current_span(op: SPAN_PREFIX + event_name, start_timestamp: payload[START_TIMESTAMP_NAME], description: payload[:sql], duration: duration) do |span|
              span.set_data(:connection_id, payload[:connection_id])
              span.set_tag(:cached, true) if payload.fetch(:cached, false) # cached key is only set for hits in the QueryCache, from Rails 5.1
            end
          end
        end
      end
    end
  end
end
