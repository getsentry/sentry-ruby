# frozen_string_literal: true

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
    let(:ctx) { ::OpenTelemetry::Context.empty }

    it 'returns unchanged context without sentry-trace' do
      carrier = {}
      updated_ctx = subject.extract(carrier, context: ctx)
      expect(updated_ctx).to eq(ctx)
    end

    it 'returns unchanged context with invalid sentry-trace' do
      carrier = { 'sentry-trace' => '000-000-0' }
      updated_ctx = subject.extract(carrier, context: ctx)
      expect(updated_ctx).to eq(ctx)
    end

    context 'with only sentry-trace header' do
      let(:carrier) do
        { 'sentry-trace' => 'd4cda95b652f4a1592b449d5929fda1b-6e0c63257de34c92-1' }
      end

      it 'returns context with sentry-trace data' do
        updated_ctx = subject.extract(carrier, context: ctx)

        sentry_trace_data = updated_ctx[described_class::SENTRY_TRACE_KEY]
        expect(sentry_trace_data).not_to be_nil

        trace_id, parent_span_id, parent_sampled = sentry_trace_data
        expect(trace_id).to eq('d4cda95b652f4a1592b449d5929fda1b')
        expect(parent_span_id).to eq('6e0c63257de34c92')
        expect(parent_sampled).to eq(true)
      end

      it 'returns context with empty frozen baggage' do
        updated_ctx = subject.extract(carrier, context: ctx)

        baggage = updated_ctx[described_class::SENTRY_BAGGAGE_KEY]
        expect(baggage).to be_a(Sentry::Baggage)
        expect(baggage.items).to eq({})
        expect(baggage.mutable).to eq(false)
      end

      it 'returns context with correct span_context' do
        updated_ctx = subject.extract(carrier, context: ctx)

        span_context = ::OpenTelemetry::Trace.current_span(updated_ctx).context
        expect(span_context.valid?).to eq(true)
        expect(span_context.hex_trace_id).to eq('d4cda95b652f4a1592b449d5929fda1b')
        expect(span_context.hex_span_id).to eq('6e0c63257de34c92')
        expect(span_context.trace_flags.sampled?).to eq(true)
        expect(span_context.remote?).to eq(true)
      end
    end

    context 'with sentry-trace and baggage headers' do
      let(:carrier) do
        {
          'sentry-trace' => 'd4cda95b652f4a1592b449d5929fda1b-6e0c63257de34c92-1',
          'baggage' => 'other-vendor-value-1=foo;bar;baz, '\
                       'sentry-trace_id=d4cda95b652f4a1592b449d5929fda1b, '\
                       'sentry-public_key=49d0f7386ad645858ae85020e393bef3, '\
                       'sentry-sample_rate=0.01337, '\
                       'sentry-user_id=Am%C3%A9lie, '\
                       'other-vendor-value-2=foo;bar;'
        }
      end

      it 'returns context with baggage' do
        updated_ctx = subject.extract(carrier, context: ctx)

        baggage = updated_ctx[described_class::SENTRY_BAGGAGE_KEY]
        expect(baggage).to be_a(Sentry::Baggage)
        expect(baggage.mutable).to eq(false)
        expect(baggage.items).to eq({
          'sample_rate' => '0.01337',
          'public_key' => '49d0f7386ad645858ae85020e393bef3',
          'trace_id' => 'd4cda95b652f4a1592b449d5929fda1b',
          'user_id' => 'Amélie'
        })
      end
    end
  end

  describe '#fields' do
    it 'returns header names' do
      expect(subject.fields).to eq(['sentry-trace', 'baggage'])
    end
  end
end
