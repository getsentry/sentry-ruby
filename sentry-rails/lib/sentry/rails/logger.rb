# frozen_string_literal: true

require "sentry/rails/log_subscriber"
require "sentry/rails/log_subscribers/active_record_subscriber"
require "sentry/rails/log_subscribers/action_controller_subscriber"
require "sentry/rails/log_subscribers/action_mailer_subscriber"
require "sentry/rails/log_subscribers/active_job_subscriber"

module Sentry
  module Rails
    class Logger
      class << self
        # Subscribe to tracing events for structured logging
        def subscribe_tracing_events
          return unless Sentry.configuration.rails.structured_logging.enabled?
          return unless Sentry.configuration.enable_logs

          attach_to = Sentry.configuration.rails.structured_logging.attach_to

          # Map of component names to their corresponding LogSubscriber classes
          subscriber_map = {
            active_record: LogSubscribers::ActiveRecordSubscriber,
            action_controller: LogSubscribers::ActionControllerSubscriber,
            action_mailer: LogSubscribers::ActionMailerSubscriber,
            active_job: LogSubscribers::ActiveJobSubscriber
          }

          # Attach subscribers for each enabled component
          attach_to.each do |component|
            if subscriber_class = subscriber_map[component]
              subscriber_class.attach_to component
            else
              Sentry.configuration.sdk_logger.warn("Unknown structured logging component: #{component}")
            end
          end
        rescue => e
          Sentry.configuration.sdk_logger.error("Failed to subscribe to tracing events: #{e.message}")
          Sentry.configuration.sdk_logger.error(e.backtrace.join("\n"))
        end

        # Unsubscribe from tracing events
        def unsubscribe_tracing_events
          # LogSubscribers automatically handle unsubscription through Rails' mechanism
          # We can manually detach if needed
          subscriber_map = {
            active_record: LogSubscribers::ActiveRecordSubscriber,
            action_controller: LogSubscribers::ActionControllerSubscriber,
            action_mailer: LogSubscribers::ActionMailerSubscriber,
            active_job: LogSubscribers::ActiveJobSubscriber
          }

          subscriber_map.each do |component, subscriber_class|
            if defined?(subscriber_class)
              subscriber_class.detach_from component
            end
          end
        rescue => e
          Sentry.configuration.sdk_logger.debug("Error during unsubscribe: #{e.message}")
        end
      end
    end
  end
end
