# frozen_string_literal: true

module Sentry
  module OpenTelemetry
    class OTLPPropagator
      FIELDS = [SENTRY_TRACE_HEADER_NAME, BAGGAGE_HEADER_NAME].freeze
      SENTRY_TRACE_KEY = Propagator::SENTRY_TRACE_KEY
      SENTRY_BAGGAGE_KEY = Propagator::SENTRY_BAGGAGE_KEY

      def inject(
        carrier,
        context: ::OpenTelemetry::Context.current,
        setter: ::OpenTelemetry::Context::Propagation.text_map_setter
      )
        span_context = ::OpenTelemetry::Trace.current_span(context).context
        return unless span_context.valid?

        sampled = span_context.trace_flags.sampled? ? "1" : "0"
        sentry_trace = "#{span_context.hex_trace_id}-#{span_context.hex_span_id}-#{sampled}"
        setter.set(carrier, SENTRY_TRACE_HEADER_NAME, sentry_trace)

        baggage = context[SENTRY_BAGGAGE_KEY]
        if baggage.is_a?(Sentry::Baggage)
          baggage_string = baggage.serialize
          setter.set(carrier, BAGGAGE_HEADER_NAME, baggage_string) if baggage_string && !baggage_string.empty?
        end
      end

      def extract(
        carrier,
        context: ::OpenTelemetry::Context.current,
        getter: ::OpenTelemetry::Context::Propagation.text_map_getter
      )
        sentry_trace = getter.get(carrier, SENTRY_TRACE_HEADER_NAME)
        return context unless sentry_trace

        sentry_trace_data = PropagationContext.extract_sentry_trace(sentry_trace)
        return context unless sentry_trace_data

        context = context.set_value(SENTRY_TRACE_KEY, sentry_trace_data)
        trace_id, span_id, _parent_sampled = sentry_trace_data

        span_context = ::OpenTelemetry::Trace::SpanContext.new(
          trace_id: [trace_id].pack("H*"),
          span_id: [span_id].pack("H*"),
          trace_flags: ::OpenTelemetry::Trace::TraceFlags::SAMPLED,
          remote: true
        )

        baggage_header = getter.get(carrier, BAGGAGE_HEADER_NAME)

        baggage =
          if baggage_header && !baggage_header.empty?
            Baggage.from_incoming_header(baggage_header)
          else
            Baggage.new({})
          end

        baggage.freeze!
        context = context.set_value(SENTRY_BAGGAGE_KEY, baggage)

        span = ::OpenTelemetry::Trace.non_recording_span(span_context)
        ::OpenTelemetry::Trace.context_with_span(span, parent_context: context)
      end

      def fields
        FIELDS
      end
    end
  end
end
