# frozen_string_literal: true

require "support/shared_examples_for_telemetry_event_buffers"

RSpec.describe Sentry::MetricEventBuffer do
  subject { described_class.new(Sentry.configuration, client) }

  include_examples "telemetry event buffer",
    event_factory: -> {
      Sentry::MetricEvent.new(
        name: "test.metric",
        type: :counter,
        value: 1
      )
    },
    max_items_config: :max_metric_events,
    enable_config: :enable_metrics
end
