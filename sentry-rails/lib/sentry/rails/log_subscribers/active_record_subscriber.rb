# frozen_string_literal: true

require "sentry/rails/log_subscriber"
require "sentry/rails/log_subscribers/parameter_filter"

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
      #     config.rails.structured_logging.subscribers = { active_record: Sentry::Rails::LogSubscribers::ActiveRecordSubscriber }
      #   end
      class ActiveRecordSubscriber < Sentry::Rails::LogSubscriber
        include ParameterFilter

        EXCLUDED_NAMES = ["SCHEMA", "TRANSACTION"].freeze
        EMPTY_ARRAY = [].freeze

        # Handle sql.active_record events
        #
        # @param event [ActiveSupport::Notifications::Event] The SQL event
        def sql(event)
          return unless Sentry.initialized?
          return if logger && !logger.info?
          return if EXCLUDED_NAMES.include?(event.payload[:name])

          sql = event.payload[:sql]
          statement_name = event.payload[:name]

          # Rails 5.0.0 doesn't include :cached in the payload, it was added in Rails 5.1
          cached = event.payload.fetch(:cached, false)
          connection_id = event.payload[:connection_id]

          attributes = {
            sql: sql,
            duration_ms: duration_ms(event),
            cached: cached
          }

          binds = event.payload[:binds]

          if Sentry.configuration.send_default_pii && (binds && !binds.empty?)
            type_casted_binds = type_casted_binds(event)

            type_casted_binds.each_with_index do |value, index|
              bind = binds[index]
              name = bind.respond_to?(:name) ? bind.name : index.to_s

              attributes["db.query.parameter.#{name}"] = value.to_s
            end
          end

          attributes[:statement_name] = statement_name if statement_name && statement_name != "SQL"
          attributes[:connection_id] = connection_id if connection_id

          maybe_add_db_config_attributes(attributes, event.payload)

          message = build_log_message(statement_name)

          log_structured_event(
            message: message,
            level: :info,
            attributes: attributes
          )
        rescue => e
          log_debug("[#{self.class}] failed to log sql event: #{e.message}")
        end

        def type_casted_binds(event)
          binds = event.payload[:type_casted_binds]

          # When a query is cached, binds are a callable,
          # and under JRuby they're always a callable.
          if binds.respond_to?(:call)
            binds.call
          else
            binds
          end
        end

        private

        def build_log_message(statement_name)
          if statement_name && statement_name != "SQL"
            "Database query: #{statement_name}"
          else
            "Database query"
          end
        end

        def maybe_add_db_config_attributes(attributes, payload)
          db_config = extract_db_config(payload)

          return unless db_config

          attributes[:db_system] = db_config[:adapter] if db_config[:adapter]

          if db_config[:database]
            db_name = db_config[:database]

            if db_config[:adapter] == "sqlite3" && db_name.include?("/")
              db_name = File.basename(db_name)
            end

            attributes[:db_name] = db_name
          end

          attributes[:server_address] = db_config[:host] if db_config[:host]
          attributes[:server_port] = db_config[:port] if db_config[:port]
          attributes[:server_socket_address] = db_config[:socket] if db_config[:socket]
        rescue => e
          log_debug("[#{self.class}] failed to add DB config attributes: #{e.message}")
        end

        def extract_db_config(payload)
          connection = payload[:connection]

          return unless connection

          extract_db_config_from_connection(connection)
        rescue => e
          log_debug("[#{self.class}] failed to extract DB config: #{e.message}")
          nil
        end

        if ::Rails.version.to_f >= 6.1
          def extract_db_config_from_connection(connection)
            if connection.pool.respond_to?(:db_config)
              db_config = connection.pool.db_config
              if db_config.respond_to?(:configuration_hash)
                return db_config.configuration_hash
              elsif db_config.respond_to?(:config)
                return db_config.config
              end
            end

            extract_db_config_fallback(connection)
          end
        else
          # Rails 6.0 and earlier use spec API
          def extract_db_config_from_connection(connection)
            if connection.pool.respond_to?(:spec)
              spec = connection.pool.spec
              if spec.respond_to?(:config)
                return spec.config
              end
            end

            extract_db_config_fallback(connection)
          end
        end

        def extract_db_config_fallback(connection)
          connection.config if connection.respond_to?(:config)
        end
      end
    end
  end
end
