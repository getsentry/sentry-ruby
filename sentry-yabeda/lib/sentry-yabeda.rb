# frozen_string_literal: true

require "yabeda"
require "sentry-ruby"
require "sentry/integrable"
require "sentry/yabeda/version"
require "sentry/yabeda/adapter"
require "sentry/yabeda/collector"

module Sentry
  module Yabeda
    extend Sentry::Integrable

    register_integration name: "yabeda", version: Sentry::Yabeda::VERSION

    class << self
      attr_accessor :collector

      # Start periodic collection of Yabeda gauge metrics.
      # Call this after Sentry.init to begin pushing runtime metrics
      # (GC, GVL, Puma stats, etc.) to Sentry.
      def start_collector!(interval: Collector::DEFAULT_INTERVAL)
        raise ArgumentError, "call start_collector! after Sentry.init" unless Sentry.initialized?

        @collector&.kill
        @collector = Collector.new(interval: interval)
      end

      def stop_collector!
        @collector&.kill
        @collector = nil
      end
    end
  end
end

::Yabeda.register_adapter(:sentry, Sentry::Yabeda::Adapter.new)
