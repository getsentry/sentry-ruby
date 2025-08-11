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
      class << self
        # Override attach_to to ensure our logger is set
        def attach_to(namespace, subscriber = new, notifier = ActiveSupport::Notifications, inherit_all: false)
          # Set the logger to nil to prevent Rails from logging to the standard logger
          # We'll handle logging through Sentry's structured logger instead
          @logger = nil
          super
        end

        # Override detach_from to properly clean up subscriptions
        def detach_from(namespace, notifier = ActiveSupport::Notifications)
          super
        end

        # Override logger to return nil, preventing standard Rails logging
        def logger
          nil
        end
      end

      protected

      # Log a structured event using Sentry's structured logger
      #
      # @param message [String] The log message
      # @param level [Symbol] The log level (:trace, :debug, :info, :warn, :error, :fatal)
      # @param attributes [Hash] Additional structured attributes to include
      def log_structured_event(message:, level: :info, attributes: {})
        return unless Sentry.configuration.enable_logs

        Sentry.logger.public_send(level, message, **attributes)
      rescue => e
        # Silently handle any errors in logging to avoid breaking the application
        Sentry.configuration.sdk_logger.debug("Failed to log structured event: #{e.message}")
      end

      # Check if an event should be excluded from logging
      #
      # @param event [ActiveSupport::Notifications::Event] The event to check
      # @return [Boolean] true if the event should be excluded
      def excluded_event?(event)
        # Skip Rails' internal events
        return true if event.name.start_with?("!")

        false
      end

      # Calculate duration in milliseconds from an event
      #
      # @param event [ActiveSupport::Notifications::Event] The event
      # @return [Float] Duration in milliseconds
      def duration_ms(event)
        event.duration.round(2)
      end

      # Determine log level based on duration (for performance-sensitive events)
      #
      # @param duration_ms [Float] Duration in milliseconds
      # @param slow_threshold [Float] Threshold in milliseconds to consider "slow"
      # @return [Symbol] Log level (:info or :warn)
      def level_for_duration(duration_ms, slow_threshold = 1000.0)
        duration_ms > slow_threshold ? :warn : :info
      end
    end
  end
end
