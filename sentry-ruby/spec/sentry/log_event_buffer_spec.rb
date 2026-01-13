# frozen_string_literal: true

require "support/shared_examples_for_telemetry_event_buffers"

RSpec.describe Sentry::LogEventBuffer do
  subject { described_class.new(Sentry.configuration, client) }

  include_examples "telemetry event buffer",
    event_factory: -> {
      Sentry::LogEvent.new(
        level: :info,
        body: "Test message"
      )
    },
    max_items_config: :max_log_events,
    enable_config: :enable_logs
end
