# frozen_string_literal: true

require "sentry/rails/log_subscriber"

module Sentry
  module Rails
    module LogSubscribers
      # LogSubscriber for ActionController events that captures HTTP request processing
      # and logs them using Sentry's structured logging system.
      #
      # This subscriber captures process_action.action_controller events and formats them
      # with relevant request information including controller, action, HTTP status,
      # request parameters, and performance metrics.
      #
      # @example Usage
      #   # Enable structured logging for ActionController
      #   Sentry.init do |config|
      #     config.enable_logs = true
      #     config.rails.structured_logging = true
      #     config.rails.structured_logging.attach_to = [:action_controller]
      #   end
      class ActionControllerSubscriber < Sentry::Rails::LogSubscriber
        # Handle process_action.action_controller events
        #
        # @param event [ActiveSupport::Notifications::Event] The controller action event
        def process_action(event)
          return if excluded_event?(event)

          payload = event.payload
          controller = payload[:controller]
          action = payload[:action]
          status = payload[:status]
          duration = duration_ms(event)

          # Prepare structured attributes
          attributes = {
            controller: controller,
            action: action,
            status: status,
            duration_ms: duration,
            method: payload[:method],
            path: payload[:path],
            format: payload[:format]
          }

          # Add view and database timing if available
          attributes[:view_runtime_ms] = payload[:view_runtime]&.round(2) if payload[:view_runtime]
          attributes[:db_runtime_ms] = payload[:db_runtime]&.round(2) if payload[:db_runtime]

          # Add request parameters if configured to send PII
          if Sentry.configuration.send_default_pii && payload[:params]
            # Filter out sensitive parameters
            filtered_params = filter_sensitive_params(payload[:params])
            attributes[:params] = filtered_params unless filtered_params.empty?
          end

          # Determine log level based on status code and duration
          level = level_for_request(status, duration)
          message = "#{controller}##{action}"

          # Log the structured event
          log_structured_event(
            message: message,
            level: level,
            attributes: attributes
          )
        end

        private

        # Determine log level based on HTTP status and duration
        #
        # @param status [Integer] HTTP status code
        # @param duration_ms [Float] Request duration in milliseconds
        # @return [Symbol] Log level
        def level_for_request(status, duration_ms)
          # Error status codes get warn/error level
          return :error if status >= 500
          return :warn if status >= 400

          # Slow requests get warn level
          return :warn if duration_ms > 5000 # 5 seconds

          :info
        end

        # Filter sensitive parameters from request params
        #
        # @param params [Hash] Request parameters
        # @return [Hash] Filtered parameters
        def filter_sensitive_params(params)
          return {} unless params.is_a?(Hash)

          # Common sensitive parameter names to exclude
          sensitive_keys = %w[
            password password_confirmation
            secret token api_key
            credit_card ssn social_security_number
            authorization auth
          ]

          params.reject do |key, _value|
            key_str = key.to_s.downcase
            sensitive_keys.any? { |sensitive| key_str.include?(sensitive) }
          end
        end
      end
    end
  end
end
