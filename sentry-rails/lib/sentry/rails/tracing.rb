require "sentry/rails/tracing/abstract_subscriber"
require "sentry/rails/tracing/active_record_subscriber"

module Sentry
  module Rails
    module Tracing
      def self.subscribe_tracing_events
        # need to avoid duplicated subscription
        return if @subscribed

        Tracing::ActiveRecordSubscriber.subscribe!

        @subscribed = true
      end
    end
  end
end
