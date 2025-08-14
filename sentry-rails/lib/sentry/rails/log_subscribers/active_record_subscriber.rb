# frozen_string_literal: true

require "sentry/rails/log_subscriber"

module Sentry
  module Rails
    module LogSubscribers
      # LogSubscriber for ActiveRecord events that captures database queries
      # and logs them using Sentry's structured logging system.
      #
      # This subscriber captures sql.active_record events and formats them
      # with relevant database information including SQL queries, duration,
      # database configuration, and caching information.
      #
      # @example Usage
      #   # Automatically attached when structured logging is enabled for :active_record
      #   Sentry.init do |config|
      #     config.enable_logs = true
      #     config.rails.structured_logging = true
      #     config.rails.structured_logging.attach_to = [:active_record]
      #   end
      class ActiveRecordSubscriber < Sentry::Rails::LogSubscriber
        EXCLUDED_EVENTS = ["SCHEMA", "TRANSACTION"].freeze

        # Handle sql.active_record events
        #
        # @param event [ActiveSupport::Notifications::Event] The SQL event
        def sql(event)
          return if excluded_event?(event)

          sql = event.payload[:sql]
          statement_name = event.payload[:name]
          cached = event.payload.fetch(:cached, false)
          connection_id = event.payload[:connection_id]
          duration = duration_ms(event)

          db_config = extract_db_config(event.payload)

          attributes = {
            sql: sql,
            duration_ms: duration,
            cached: cached
          }

          attributes[:statement_name] = statement_name if statement_name && statement_name != "SQL"
          attributes[:connection_id] = connection_id if connection_id

          add_db_config_attributes(attributes, db_config)

          message = build_log_message(statement_name)

          log_structured_event(
            message: message,
            level: :info,
            attributes: attributes
          )
        end

        protected

        def excluded_event?(event)
          return true if super
          return true if EXCLUDED_EVENTS.include?(event.payload[:name])

          false
        end

        private

        def build_log_message(statement_name)
          if statement_name && statement_name != "SQL"
            "Database query: #{statement_name}"
          else
            "Database query"
          end
        end

        def extract_db_config(payload)
          connection = payload[:connection]

          if payload[:connection_id] && !connection
            connection = ActiveRecord::Base.connection_pool.connections.find do |conn|
              conn.object_id == payload[:connection_id]
            end
          end

          return nil unless connection

          if connection.pool.respond_to?(:db_config)
            connection.pool.db_config.configuration_hash
          elsif connection.pool.respond_to?(:spec)
            connection.pool.spec.config
          end
        rescue => e
          Sentry.configuration.sdk_logger.debug("Failed to extract db config: #{e.message}")
          nil
        end

        def add_db_config_attributes(attributes, db_config)
          return unless db_config

          attributes[:db_system] = db_config[:adapter] if db_config[:adapter]
          attributes[:db_name] = db_config[:database] if db_config[:database]
          attributes[:server_address] = db_config[:host] if db_config[:host]
          attributes[:server_port] = db_config[:port] if db_config[:port]
          attributes[:server_socket_address] = db_config[:socket] if db_config[:socket]
        end
      end
    end
  end
end
