# frozen_string_literal: true

require "active_support/log_subscriber"

module Sentry
  module Rails
    # Base class for Sentry log subscribers that extends ActiveSupport::LogSubscriber
    # to provide structured logging capabilities for Rails components.
    #
    # This class follows Rails' LogSubscriber pattern and provides common functionality
    # for capturing Rails instrumentation events and logging them through Sentry's
    # structured logging system.
    #
    # @example Creating a custom log subscriber
    #   class MySubscriber < Sentry::Rails::LogSubscriber
    #     attach_to :my_component
    #
    #     def my_event(event)
    #       log_structured_event(
    #         message: "My event occurred",
    #         level: :info,
    #         attributes: {
    #           duration_ms: event.duration,
    #           custom_data: event.payload[:custom_data]
    #         }
    #       )
    #     end
    #   end
    class LogSubscriber < ActiveSupport::LogSubscriber
      ORIGIN = "auto.logger.rails.log_subscriber"

      class << self
        if ::Rails.version.to_f < 6.0
          # Rails 5.x does not provide detach_from
          def detach_from(namespace, notifications = ActiveSupport::Notifications)
            listeners = public_instance_methods(false)
              .flat_map { |key|
                notifications.notifier.listeners_for("#{key}.#{namespace}")
              }
              .select { |listener| listener.instance_variable_get(:@delegate).is_a?(self) }

            listeners.map do |listener|
              notifications.notifier.unsubscribe(listener)
            end
          end
        end
      end

      protected

      # Log a structured event using Sentry's structured logger
      #
      # @param message [String] The log message
      # @param level [Symbol] The log level (:trace, :debug, :info, :warn, :error, :fatal)
      # @param attributes [Hash] Additional structured attributes to include
      # @param origin [String] The origin of the log event
      def log_structured_event(message:, level: :info, attributes: {}, origin: ORIGIN)
        Sentry.logger.public_send(level, message, **attributes, origin: origin)
      rescue => e
        # Silently handle any errors in logging to avoid breaking the application
        Sentry.configuration.sdk_logger.debug("Failed to log structured event: #{e.message}")
      end

      # Calculate duration in milliseconds from an event
      #
      # @param event [ActiveSupport::Notifications::Event] The event
      # @return [Float] Duration in milliseconds
      def duration_ms(event)
        event.duration.round(2)
      end
    end
  end
end
