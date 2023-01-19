# frozen_string_literal: true

require 'singleton'

module Sentry
  module OpenTelemetry
    TraceData = Struct.new(:trace_id, :span_id, :parent_span_id, :parent_sampled, :baggage)

    class SpanProcessor < ::OpenTelemetry::SDK::Trace::SpanProcessor
      include Singleton

      SEMANTIC_CONVENTIONS = ::OpenTelemetry::SemanticConventions::Trace
      INTERNAL_SPAN_KINDS = %i(client internal)

      # The mapping from otel span ids to sentry spans
      # @return [Hash]
      attr_reader :span_map

      def initialize
        @span_map = {}
        setup_event_processor
      end

      def on_start(otel_span, parent_context)
        return unless Sentry.initialized? && Sentry.configuration.instrumenter == :otel
        return unless otel_span.context.valid?
        return if from_sentry_sdk?(otel_span)

        trace_data = get_trace_data(otel_span, parent_context)

        sentry_parent_span = @span_map[trace_data.parent_span_id] if trace_data.parent_span_id

        sentry_span = if sentry_parent_span
          sentry_parent_span.start_child(
            span_id: trace_data.span_id,
            description: otel_span.name,
            start_timestamp: otel_span.start_timestamp / 1e9
          )
        else
          options = {
            instrumenter: :otel,
            name: otel_span.name,
            span_id: trace_data.span_id,
            trace_id: trace_data.trace_id,
            parent_span_id: trace_data.parent_span_id,
            parent_sampled: trace_data.parent_sampled,
            baggage: trace_data.baggage,
            start_timestamp: otel_span.start_timestamp / 1e9
          }

          Sentry.start_transaction(**options)
        end

        @span_map[trace_data.span_id] = sentry_span
      end

      def on_finish(otel_span)
        return unless Sentry.initialized? && Sentry.configuration.instrumenter == :otel
        return unless otel_span.context.valid?

        sentry_span = @span_map.delete(otel_span.context.hex_span_id)
        return unless sentry_span

        if sentry_span.is_a?(Sentry::Transaction)
          update_transaction_with_otel_data(sentry_span, otel_span)
        else
          update_span_with_otel_data(sentry_span, otel_span)
        end

        sentry_span.finish(end_timestamp: otel_span.end_timestamp / 1e9)
      end

      def clear
        @span_map = {}
      end

      private

      def from_sentry_sdk?(otel_span)
        dsn = Sentry.configuration.dsn
        return false unless dsn

        if otel_span.name.start_with?("HTTP")
          # only check client requests, connects are sometimes internal
          return false unless INTERNAL_SPAN_KINDS.include?(otel_span.kind)

          address = otel_span.attributes[SEMANTIC_CONVENTIONS::NET_PEER_NAME]

          # if no address drop it, just noise
          return true unless address
          return true if dsn.host == address
        end

        false
      end

      def get_trace_data(otel_span, parent_context)
        trace_data = TraceData.new
        trace_data.span_id = otel_span.context.hex_span_id
        trace_data.trace_id = otel_span.context.hex_trace_id

        unless otel_span.parent_span_id == ::OpenTelemetry::Trace::INVALID_SPAN_ID
          trace_data.parent_span_id = otel_span.parent_span_id.unpack1("H*")
        end

        sentry_trace_data = parent_context[Propagator::SENTRY_TRACE_KEY]
        trace_data.parent_sampled = sentry_trace_data[2] if sentry_trace_data

        trace_data.baggage = parent_context[Propagator::SENTRY_BAGGAGE_KEY]

        trace_data
      end

      def otel_context_hash(otel_span)
        otel_context = {}
        otel_context[:attributes] = otel_span.attributes unless otel_span.attributes.empty?

        resource_attributes = otel_span.resource.attribute_enumerator.to_h
        otel_context[:resource] = resource_attributes unless resource_attributes.empty?

        otel_context
      end

      def parse_span_description(otel_span)
        op = otel_span.name
        description = otel_span.name

        if (http_method = otel_span.attributes[SEMANTIC_CONVENTIONS::HTTP_METHOD])
          op = "http.#{otel_span.kind}"
          description = http_method

          peer_name = otel_span.attributes[SEMANTIC_CONVENTIONS::NET_PEER_NAME]
          description += " #{peer_name}" if peer_name

          target = otel_span.attributes[SEMANTIC_CONVENTIONS::HTTP_TARGET]
          description += target if target
        elsif otel_span.attributes[SEMANTIC_CONVENTIONS::DB_SYSTEM]
          op = "db"

          statement = otel_span.attributes[SEMANTIC_CONVENTIONS::DB_STATEMENT]
          description = statement if statement
        end

        [op, description]
      end

      def update_span_status(sentry_span, otel_span)
        if (http_status_code = otel_span.attributes[SEMANTIC_CONVENTIONS::HTTP_STATUS_CODE])
          sentry_span.set_http_status(http_status_code)
        elsif (status_code = otel_span.status.code)
          status = [0, 1].include?(status_code) ? 'ok' : 'unknown_error'
          sentry_span.set_status(status)
        end
      end

      def update_span_with_otel_data(sentry_span, otel_span)
        update_span_status(sentry_span, otel_span)
        sentry_span.set_data('otel.kind', otel_span.kind)
        otel_span.attributes&.each { |k, v| sentry_span.set_data(k, v) }

        op, description = parse_span_description(otel_span)
        sentry_span.set_op(op)
        sentry_span.set_description(description)
      end

      def update_transaction_with_otel_data(transaction, otel_span)
        update_span_status(transaction, otel_span)
        transaction.set_context(:otel, otel_context_hash(otel_span))

        op, _ = parse_span_description(otel_span)
        transaction.set_op(op)
        transaction.set_name(otel_span.name)
      end

      def setup_event_processor
        Sentry.add_global_event_processor do |event, _hint|
          span_context = ::OpenTelemetry::Trace.current_span.context
          next event unless span_context.valid?

          sentry_span = @span_map[span_context.hex_span_id]
          next event unless sentry_span

          event.contexts[:trace] ||= sentry_span.get_trace_context
          event
        end
      end
    end
  end
end
