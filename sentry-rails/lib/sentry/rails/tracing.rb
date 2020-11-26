require "sentry/rails/tracing/abstract_subscriber"
require "sentry/rails/tracing/active_record_subscriber"
require "sentry/rails/tracing/action_controller_subscriber"
require "sentry/rails/tracing/action_view_subscriber"

module Sentry
  module Rails
    module Tracing
      AVAILABLE_SUBSCRIBERS = [ActionViewSubscriber, ActiveRecordSubscriber, ActionControllerSubscriber]

      def self.subscribe_tracing_events
        # need to avoid duplicated subscription
        return if @subscribed

        AVAILABLE_SUBSCRIBERS.each(&:subscribe!)

        @subscribed = true
      end

      def self.unsubscribe_tracing_events
        return unless @subscribed

        AVAILABLE_SUBSCRIBERS.each(&:unsubscribe!)

        @subscribed = false
      end

      # this is necessary because instrumentation events don't record absolute start/finish time
      # so we need to retrieve the correct time this way
      def self.patch_active_support_notifications
        unless ::ActiveSupport::Notifications::Instrumenter.ancestors.include?(SentryNotificationExtension)
          ::ActiveSupport::Notifications::Instrumenter.send(:prepend, SentryNotificationExtension)
        end

        SentryNotificationExtension.module_eval do
          def instrument(name, payload = {}, &block)
            is_public_event = name[0] != "!"

            payload[:start_timestamp] = Time.now.utc.to_f if is_public_event

            super(name, payload, &block)
          end
        end
      end

      def self.remove_active_support_notifications_patch
        if ::ActiveSupport::Notifications::Instrumenter.ancestors.include?(SentryNotificationExtension)
          SentryNotificationExtension.module_eval do
            def instrument(name, payload = {}, &block)
              super
            end
          end
        end
      end

      def self.get_current_transaction
        Sentry.get_current_scope.get_transaction
      end

      # it's just a container for the extended method
      module SentryNotificationExtension
      end
    end
  end
end
