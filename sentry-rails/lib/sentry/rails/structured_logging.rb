# frozen_string_literal: true

require "sentry/rails/log_subscriber"
require "sentry/rails/log_subscribers/active_record_subscriber"
require "sentry/rails/log_subscribers/action_controller_subscriber"
require "sentry/rails/log_subscribers/action_mailer_subscriber"
require "sentry/rails/log_subscribers/active_job_subscriber"

module Sentry
  module Rails
    module StructuredLogging
      SUBSCRIBERS = {
        active_record: LogSubscribers::ActiveRecordSubscriber,
        action_controller: LogSubscribers::ActionControllerSubscriber,
        action_mailer: LogSubscribers::ActionMailerSubscriber,
        active_job: LogSubscribers::ActiveJobSubscriber
      }

      def self.attach(config)
        config.attach_to.each do |component|
          if subscriber_class = SUBSCRIBERS[component]
            subscriber_class.attach_to component
          else
            Sentry.configuration.sdk_logger.warn("Unknown structured logging component: #{component}")
          end
        end
      rescue => e
        Sentry.configuration.sdk_logger.error("Failed to attach structured loggers: #{e.message}")
        Sentry.configuration.sdk_logger.error(e.backtrace.join("\n"))
      end

      def self.detach
        SUBSCRIBERS.each do |component, subscriber_class|
          subscriber_class.detach_from component
        end
      rescue => e
        Sentry.configuration.sdk_logger.debug("Error during detaching loggers: #{e.message}")
      end
    end
  end
end
