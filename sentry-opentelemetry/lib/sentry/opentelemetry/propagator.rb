module Sentry
  module OpenTelemetry
    class Propagator

      FIELDS = [SENTRY_TRACE_HEADER_NAME, BAGGAGE_HEADER_NAME].freeze

      SENTRY_TRACE_PARENT_KEY = ::OpenTelemetry::Context.create_key('sentry-trace-parent')
      SENTRY_DSC_KEY = ::OpenTelemetry::Context.create_key('sentry-dsc')

      def inject(carrier,
                 context: ::OpenTelemetry::Context.current,
                 setter: ::OpenTelemetry::Context::Propagation.text_map_setter)

        span_context = ::OpenTelemetry::Trace.current_span(context).context
        return unless span_context.valid?

        sampled_flag = span_context.trace_flags.sampled? ? 1 : 0 unless span_context.trace_flags.nil?
        sentry_trace = "#{span_context.hex_trace_id}-#{span_context.hex_span_id}-#{sampled_flag}"

        setter.set(carrier, SENTRY_TRACE_HEADER_NAME, sentry_trace)
      end

      def extract(carrier,
                  context: ::OpenTelemetry::Context.current,
                  getter: ::OpenTelemetry::Context::Propagation.text_map_getter)

        sentry_trace = getter.get(carrier, SENTRY_TRACE_HEADER_NAME)
        return context unless sentry_trace

        sentry_trace_data = Transaction.extract_sentry_trace(sentry_trace)
        return unless sentry_trace_data

        context = context.set_value(SENTRY_TRACE_PARENT_KEY, sentry_trace_data)
        trace_id, parent_span_id, parent_sampled = sentry_trace_data

        trace_flags = if parent_sampled.nil?
                        nil
                      elsif parent_sampled
                        ::OpenTelemetry::Trace::TraceFlags::SAMPLED
                      else
                        ::OpenTelemetry::Trace::TraceFlags::DEFAULT
                      end

        span_context = ::OpenTelemetry::Trace::SpanContext.new(trace_id: trace_id,
                                                               span_id: parent_span_id,
                                                               trace_flags: trace_flags,
                                                               remote: true)

        span = ::OpenTelemetry::Trace.non_recording_span(span_context)
        ::OpenTelemetry::Trace.context_with_span(span, parent_context: context)

        # TODO-neel baggage
        # baggage = getter.get(carrier, SENTRY_TRACE_HEADER_NAME)
        context
      end

      def fields
        FIELDS
      end
    end
  end
end
