# frozen_string_literal: true

require "sentry/telemetry_event_buffer"

module Sentry
  # LogEventBuffer buffers log events and sends them to Sentry in a single envelope.
  #
  # This is used internally by the `Sentry::Client`.
  #
  # @!visibility private
  class LogEventBuffer < TelemetryEventBuffer
    DEFAULT_MAX_EVENTS = 100

    def initialize(configuration, client)
      super(
        configuration,
        client,
        event_class: LogEvent,
        max_items: configuration.max_log_events || DEFAULT_MAX_EVENTS,
        envelope_type: "log",
        envelope_content_type: "application/vnd.sentry.items.log+json",
        before_send: configuration.before_send_log
      )
    end
  end
end
