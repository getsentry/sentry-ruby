# frozen_string_literal: true

require "sentry/rails/log_subscriber"
require "sentry/rails/log_subscribers/action_controller_subscriber"
require "sentry/rails/log_subscribers/active_record_subscriber"
require "sentry/rails/log_subscribers/active_job_subscriber"
require "sentry/rails/log_subscribers/action_mailer_subscriber"

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
