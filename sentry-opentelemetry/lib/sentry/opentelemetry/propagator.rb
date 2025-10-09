# frozen_string_literal: true

module Sentry
  module OpenTelemetry
    class Propagator
      FIELDS = [SENTRY_TRACE_HEADER_NAME, BAGGAGE_HEADER_NAME].freeze

      SENTRY_TRACE_KEY = ::OpenTelemetry::Context.create_key("sentry-trace")
      SENTRY_BAGGAGE_KEY = ::OpenTelemetry::Context.create_key("sentry-baggage")

      def inject(
        carrier,
        context: ::OpenTelemetry::Context.current,
        setter: ::OpenTelemetry::Context::Propagation.text_map_setter
      )
        span_context = ::OpenTelemetry::Trace.current_span(context).context
        return unless span_context.valid?

        span_map = SpanProcessor.instance.span_map
        sentry_span = span_map[span_context.hex_span_id]
        return unless sentry_span

        setter.set(carrier, SENTRY_TRACE_HEADER_NAME, sentry_span.to_sentry_trace)

        baggage = sentry_span.to_baggage
        setter.set(carrier, BAGGAGE_HEADER_NAME, baggage) if baggage && !baggage.empty?
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
          # we simulate a sampled trace on the otel side and leave the sampling to sentry
          trace_flags: ::OpenTelemetry::Trace::TraceFlags::SAMPLED,
          remote: true
        )

        baggage_header = getter.get(carrier, BAGGAGE_HEADER_NAME)

        baggage =
          if baggage_header && !baggage_header.empty?
            Baggage.from_incoming_header(baggage_header)
          else
            # If there's an incoming sentry-trace but no incoming baggage header,
            # for instance in traces coming from older SDKs,
            # baggage will be empty and frozen and won't be populated as head SDK.
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
