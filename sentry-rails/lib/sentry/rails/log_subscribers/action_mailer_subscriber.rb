# frozen_string_literal: true

require "sentry/rails/log_subscriber"

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
      #     config.rails.structured_logging.attach_to = [:action_mailer]
      #   end
      class ActionMailerSubscriber < Sentry::Rails::LogSubscriber
        # Handle deliver.action_mailer events
        #
        # @param event [ActiveSupport::Notifications::Event] The email delivery event
        def deliver(event)
          return if excluded_event?(event)

          payload = event.payload
          mailer = payload[:mailer]
          duration = duration_ms(event)

          # Prepare structured attributes
          attributes = {
            mailer: mailer,
            duration_ms: duration,
            perform_deliveries: payload[:perform_deliveries]
          }

          # Add delivery method if available
          attributes[:delivery_method] = payload[:delivery_method] if payload[:delivery_method]

          # Add date if available
          attributes[:date] = payload[:date].to_s if payload[:date]

          # Only include email details if PII is allowed
          if Sentry.configuration.send_default_pii
            # Note: We're being very conservative here and not including
            # to, from, subject, or body to avoid PII leakage
            # Users can customize this behavior by extending the subscriber
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
          return if excluded_event?(event)

          payload = event.payload
          mailer = payload[:mailer]
          action = payload[:action]
          duration = duration_ms(event)

          # Prepare structured attributes
          attributes = {
            mailer: mailer,
            action: action,
            duration_ms: duration
          }

          # Add parameters if PII is allowed and they exist
          if Sentry.configuration.send_default_pii && payload[:params]
            # Filter sensitive parameters
            filtered_params = filter_sensitive_params(payload[:params])
            attributes[:params] = filtered_params unless filtered_params.empty?
          end

          message = "#{mailer}##{action}"

          # Log the structured event
          log_structured_event(
            message: message,
            level: :info,
            attributes: attributes
          )
        end

        private

        # Filter sensitive parameters from mailer params
        #
        # @param params [Hash] Mailer parameters
        # @return [Hash] Filtered parameters
        def filter_sensitive_params(params)
          return {} unless params.is_a?(Hash)

          # Email-specific sensitive parameter names to exclude
          sensitive_keys = %w[
            password token secret api_key
            email_address to from cc bcc
            subject body content message
            personal_data user_data
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
