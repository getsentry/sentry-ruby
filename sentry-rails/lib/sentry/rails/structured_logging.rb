# frozen_string_literal: true

module Sentry
  module Rails
    module StructuredLogging
      class << self
        def attach(config)
          config.subscribers.each do |component, subscriber_class|
            subscriber_class.attach_to component
          end
        rescue => e
          Sentry.configuration.sdk_logger.error("Failed to attach structured loggers: #{e.message}")
          Sentry.configuration.sdk_logger.error(e.backtrace.join("\n"))
        end

        def detach(config)
          config.subscribers.each do |component, subscriber_class|
            subscriber_class.detach_from component
          end
        rescue => e
          Sentry.configuration.sdk_logger.debug("Error during detaching loggers: #{e.message}")
        end
      end
    end
  end
end
