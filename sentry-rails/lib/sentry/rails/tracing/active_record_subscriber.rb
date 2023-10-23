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
              span.set_tag(:cached, true) if payload.fetch(:cached, false) # cached key is only set for hits in the QueryCache, from Rails 5.1

              connection = payload[:connection]

              if payload[:connection_id]
                span.set_data(:connection_id, payload[:connection_id])

                # we fallback to the base connection on rails < 6.0.0 since the payload doesn't have it
                base_connection = ActiveRecord::Base.connection
                connection ||= base_connection if payload[:connection_id] == base_connection.object_id
              end

              next unless connection

              db_config = if connection.pool.respond_to?(:db_config)
                            connection.pool.db_config.configuration_hash
                          elsif connection.pool.respond_to?(:spec)
                            connection.pool.spec.config
                          end

              next unless db_config

              span.set_data(Span::DataConventions::DB_SYSTEM, db_config[:adapter]) if db_config[:adapter]
              span.set_data(Span::DataConventions::DB_NAME, db_config[:database]) if db_config[:database]
              span.set_data(Span::DataConventions::SERVER_ADDRESS, db_config[:host]) if db_config[:host]
              span.set_data(Span::DataConventions::SERVER_PORT, db_config[:port]) if db_config[:port]
              span.set_data(Span::DataConventions::SERVER_SOCKET_ADDRESS, db_config[:socket]) if db_config[:socket]
            end
          end
        end
      end
    end
  end
end
