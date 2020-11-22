require "sentry/rails/tracing/abstract_subscriber"
require "sentry/rails/tracing/active_record_subscriber"
require "sentry/rails/tracing/action_controller_subscriber"

module Sentry
  module Rails
    module Tracing
      def self.subscribe_tracing_events
        # need to avoid duplicated subscription
        return if @subscribed

        Tracing::ActiveRecordSubscriber.subscribe!
        Tracing::ActionControllerSubscriber.subscribe!

        @subscribed = true
      end

      # this is necessary because instrumentation events don't record absolute start/finish time
      # so we need to retrieve the correct time this way
      def self.patch_active_support_notifications
        unless ::ActiveSupport::Notifications::Instrumenter.ancestors.include?(SentryNotificationExtension)
          ::ActiveSupport::Notifications::Instrumenter.send(:prepend, SentryNotificationExtension)
        end
      end

      def self.get_current_transaction
        Sentry.get_current_scope.get_transaction
      end

      module SentryNotificationExtension
        def instrument(name, payload = {}, &block)
          is_public_event = name[0] != "!"

          payload[:start_timestamp] = Time.now.utc.to_f if is_public_event

          super(name, payload, &block)
        end
      end
    end
  end
end
