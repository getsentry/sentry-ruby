# frozen_string_literal: true

require "sentry/threaded_periodic_worker"

module Sentry
  module Yabeda
    # Periodically calls Yabeda.collect! to trigger gauge collection blocks
    # registered by plugins like yabeda-puma-plugin, yabeda-gc, and
    # yabeda-gvl_metrics.
    #
    # In a pull-based system (Prometheus), the scrape request triggers
    # collection. In a push-based system (Sentry), we need this periodic
    # worker to drive the collect → gauge.set → adapter.perform_gauge_set!
    # pipeline.
    class Collector < Sentry::ThreadedPeriodicWorker
      DEFAULT_INTERVAL = 15 # seconds

      def initialize(interval: DEFAULT_INTERVAL)
        super(Sentry.sdk_logger, interval)
        ensure_thread
      end

      def run
        ::Yabeda.collect!
      rescue => e
        log_warn("[Sentry::Yabeda::Collector] collection failed: #{e.message}")
      end
    end
  end
end
