# frozen_string_literal: true

require "sentry/telemetry_event_buffer"

module Sentry
  # MetricEventBuffer buffers metric events and sends them to Sentry in a single envelope.
  #
  # This is used internally by the `Sentry::Client`.
  #
  # @!visibility private
  class MetricEventBuffer < TelemetryEventBuffer
    DEFAULT_MAX_METRICS = 1000
    MAX_METRICS_BEFORE_DROP = 10_000

    def initialize(configuration, client)
      super(
        configuration,
        client,
        event_class: MetricEvent,
        max_items: configuration.max_metric_events || DEFAULT_MAX_METRICS,
        max_items_before_drop: MAX_METRICS_BEFORE_DROP,
        envelope_type: "trace_metric",
        envelope_content_type: "application/vnd.sentry.items.trace-metric+json",
        before_send: configuration.before_send_metric
      )
    end
  end
end
