# frozen_string_literal: true

require "sentry/rails/log_subscriber"
require "sentry/rails/log_subscribers/parameter_filter"

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
      #     config.rails.structured_logging.subscribers = { action_controller: Sentry::Rails::LogSubscribers::ActionControllerSubscriber }
      #   end
      class ActionControllerSubscriber < Sentry::Rails::LogSubscriber
        include ParameterFilter

        # Handle process_action.action_controller events
        #
        # @param event [ActiveSupport::Notifications::Event] The controller action event
        def process_action(event)
          payload = event.payload

          controller = payload[:controller]
          action = payload[:action]

          status = extract_status(payload)

          attributes = {
            controller: controller,
            action: action,
            duration_ms: duration_ms(event),
            method: payload[:method],
            path: payload[:path],
            format: payload[:format]
          }

          attributes[:status] = status if status

          if payload[:view_runtime]
            attributes[:view_runtime_ms] = payload[:view_runtime].round(2)
          end

          if payload[:db_runtime]
            attributes[:db_runtime_ms] = payload[:db_runtime].round(2)
          end

          if Sentry.configuration.send_default_pii && payload[:params]
            filtered_params = filter_sensitive_params(payload[:params])
            attributes[:params] = filtered_params unless filtered_params.empty?
          end

          level = level_for_request(payload)
          message = "#{controller}##{action}"

          log_structured_event(
            message: message,
            level: level,
            attributes: attributes
          )
        end

        private

        def extract_status(payload)
          if payload[:status]
            payload[:status]
          elsif payload[:exception]
            case payload[:exception].first
            when "ActionController::RoutingError"
              404
            when "ActionController::BadRequest"
              400
            else
              500
            end
          end
        end

        def level_for_request(payload)
          status = payload[:status]

          # In Rails < 6.0 status is not set when an action raised an exception
          if status.nil? && payload[:exception]
            case payload[:exception].first
            when "ActionController::RoutingError"
              :warn
            when "ActionController::BadRequest"
              :warn
            else
              :error
            end
          elsif status.nil?
            :info
          elsif status >= 200 && status < 400
            :info
          elsif status >= 400 && status < 500
            :warn
          elsif status >= 500
            :error
          else
            :info
          end
        end
      end
    end
  end
end
