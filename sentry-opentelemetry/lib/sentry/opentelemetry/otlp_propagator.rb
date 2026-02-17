# frozen_string_literal: true

module Sentry
  module OpenTelemetry
    class OTLPPropagator < Propagator
      def inject(
        carrier,
        context: ::OpenTelemetry::Context.current,
        setter: ::OpenTelemetry::Context::Propagation.text_map_setter
      )
        span_context = ::OpenTelemetry::Trace.current_span(context).context
        return unless span_context.valid?

        setter.set(carrier, SENTRY_TRACE_HEADER_NAME, to_sentry_trace(span_context))

        baggage = context[SENTRY_BAGGAGE_KEY]
        if baggage.is_a?(Sentry::Baggage)
          baggage_string = baggage.serialize
          setter.set(carrier, BAGGAGE_HEADER_NAME, baggage_string) unless baggage_string&.empty?
        end
      end

      private

      def to_sentry_trace(span_context)
        sampled = span_context.trace_flags.sampled? ? "1" : "0"
        "#{span_context.hex_trace_id}-#{span_context.hex_span_id}-#{sampled}"
      end
    end
  end
end
