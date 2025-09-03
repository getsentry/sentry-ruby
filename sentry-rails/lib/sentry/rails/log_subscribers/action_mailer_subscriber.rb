# frozen_string_literal: true

require "sentry/rails/log_subscriber"
require "sentry/rails/log_subscribers/parameter_filter"

module Sentry
  module Rails
    module LogSubscribers
      # LogSubscriber for ActionMailer events that captures email delivery
      # and processing events using Sentry's structured logging system.
      #
      # This subscriber captures deliver.action_mailer and process.action_mailer events
      # and formats them with relevant email information while respecting PII settings.
      #
      # @example Usage
      #   # Enable structured logging for ActionMailer
      #   Sentry.init do |config|
      #     config.enable_logs = true
      #     config.rails.structured_logging = true
      #     config.rails.structured_logging.subscribers = { action_mailer: Sentry::Rails::LogSubscribers::ActionMailerSubscriber }
      #   end
      class ActionMailerSubscriber < Sentry::Rails::LogSubscriber
        include ParameterFilter

        # Handle deliver.action_mailer events
        #
        # @param event [ActiveSupport::Notifications::Event] The email delivery event
        def deliver(event)
          payload = event.payload

          mailer = payload[:mailer]

          attributes = {
            mailer: mailer,
            duration_ms: duration_ms(event),
            perform_deliveries: payload[:perform_deliveries]
          }

          attributes[:delivery_method] = payload[:delivery_method] if payload[:delivery_method]
          attributes[:date] = payload[:date].to_s if payload[:date]

          if Sentry.configuration.send_default_pii
            attributes[:message_id] = payload[:message_id] if payload[:message_id]
          end

          message = "Email delivered via #{mailer}"

          # Log the structured event
          log_structured_event(
            message: message,
            level: :info,
            attributes: attributes
          )
        end

        # Handle process.action_mailer events
        #
        # @param event [ActiveSupport::Notifications::Event] The email processing event
        def process(event)
          payload = event.payload

          mailer = payload[:mailer]
          action = payload[:action]
          duration = duration_ms(event)

          attributes = {
            mailer: mailer,
            action: action,
            duration_ms: duration
          }

          if Sentry.configuration.send_default_pii && payload[:params]
            filtered_params = filter_sensitive_params(payload[:params])
            attributes[:params] = filtered_params unless filtered_params.empty?
          end

          message = "#{mailer}##{action}"

          log_structured_event(
            message: message,
            level: :info,
            attributes: attributes
          )
        end
      end
    end
  end
end
