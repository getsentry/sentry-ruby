require 'spec_helper'

RSpec.describe Sentry::OpenTelemetry::Propagator do
  let(:tracer) { ::OpenTelemetry.tracer_provider.tracer('sentry', '1.0') }
  let(:span_processor) { Sentry::OpenTelemetry::SpanProcessor.instance }
  let(:span_map) { span_processor.span_map }

  before do
    perform_basic_setup
    perform_otel_setup
    span_map.clear
  end

  describe '#inject' do
    let(:carrier) { {} }

    it 'noops with invalid span_context' do
      subject.inject(carrier)
      expect(carrier).to eq({})
    end

    it 'noops if span not found in span_map' do
      span = tracer.start_root_span('test')
      ctx = ::OpenTelemetry::Trace.context_with_span(span)

      expect(span_map).to receive(:[]).and_call_original
      subject.inject(carrier, context: ctx)
      expect(carrier).to eq({})
    end

    context 'with running trace' do
      let(:ctx) do
        # setup root span, child span and return current context
        empty_context = ::OpenTelemetry::Context.empty
        root_span = tracer.start_root_span('test')
        span_processor.on_start(root_span, empty_context)
        root_context = ::OpenTelemetry::Trace.context_with_span(root_span, parent_context: empty_context)
        child_span = tracer.start_span('child test', with_parent: root_context)
        span_processor.on_start(child_span, root_context)
        expect(span_map.size).to eq(2)

        ::OpenTelemetry::Trace.context_with_span(child_span, parent_context: root_context)
      end

      it 'sets sentry-trace and baggage headers on carrier' do
        subject.inject(carrier, context: ctx)

        span_id = ::OpenTelemetry::Trace.current_span(ctx).context.hex_span_id
        span = span_map[span_id]

        expect(carrier['sentry-trace']).to eq(span.to_sentry_trace)
        expect(carrier['baggage']).to eq(span.to_baggage)
      end
    end
  end

  describe '#extract' do

  end

  describe '#fields' do
    it 'returns header names' do
      expect(subject.fields).to eq(['sentry-trace', 'baggage'])
    end
  end
end
