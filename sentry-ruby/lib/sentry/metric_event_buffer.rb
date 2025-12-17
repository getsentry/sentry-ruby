# frozen_string_literal: true

require "sentry/threaded_periodic_worker"

module Sentry
  # MetricEventBuffer buffers metric events and sends them to Sentry in a single envelope.
  #
  # This is used internally by the `Sentry::Client`.
  #
  # @!visibility private
  class MetricEventBuffer < ThreadedPeriodicWorker
    FLUSH_INTERVAL = 5 # seconds
    DEFAULT_MAX_METRICS = 100

    # @!visibility private
    attr_reader :pending_metrics

    def initialize(configuration, client)
      super(configuration.sdk_logger, FLUSH_INTERVAL)

      @client = client
      @pending_metrics = []
      @max_metrics = configuration.max_metric_events || DEFAULT_MAX_METRICS
      @mutex = Mutex.new

      log_debug("[Metrics] Initialized buffer with max_metrics=#{@max_metrics}, flush_interval=#{FLUSH_INTERVAL}s")
    end

    def start
      ensure_thread
      self
    end

    def flush
      @mutex.synchronize do
        return if empty?

        log_debug("[MetricEventBuffer] flushing #{size} metrics")

        send_metrics
      end
    end
    alias_method :run, :flush

    def add_metric(metric)
      raise ArgumentError, "expected a MetricEvent, got #{metric.class}" unless metric.is_a?(MetricEvent)

      @mutex.synchronize do
        @pending_metrics << metric
        send_metrics if size >= @max_metrics
      end

      self
    end

    def empty?
      @pending_metrics.empty?
    end

    def size
      @pending_metrics.size
    end

    def clear!
      @pending_metrics.clear
    end

    private

    def send_metrics
      @client.send_metrics(@pending_metrics)
    rescue => e
      log_debug("[MetricEventBuffer] Failed to send metrics: #{e.message}")
    ensure
      clear!
    end
  end
end
