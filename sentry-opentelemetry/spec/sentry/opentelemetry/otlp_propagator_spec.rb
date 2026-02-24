# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Sentry::OpenTelemetry::OTLPPropagator do
  let(:tracer) { ::OpenTelemetry.tracer_provider.tracer('sentry', '1.0') }

  before do
    perform_basic_setup
    perform_otel_setup
  end

  describe '#inject' do
    let(:carrier) { {} }

    it 'noops with invalid span_context' do
      subject.inject(carrier)
      expect(carrier).to eq({})
    end

    context 'with valid span' do
      it 'sets sentry-trace header on carrier' do
        span = tracer.start_root_span('test')
        ctx = ::OpenTelemetry::Trace.context_with_span(span)

        subject.inject(carrier, context: ctx)

        span_context = span.context
        expected_trace = "#{span_context.hex_trace_id}-#{span_context.hex_span_id}-1"
        expect(carrier['sentry-trace']).to eq(expected_trace)
      end

      it 'sets sampled flag to 0 when not sampled' do
        span = tracer.start_root_span('test')
        ctx = ::OpenTelemetry::Trace.context_with_span(span)

        allow(span.context.trace_flags).to receive(:sampled?).and_return(false)
        subject.inject(carrier, context: ctx)

        span_context = span.context
        expected_trace = "#{span_context.hex_trace_id}-#{span_context.hex_span_id}-0"
        expect(carrier['sentry-trace']).to eq(expected_trace)
      end
    end

    context 'with baggage in context' do
      it 'sets baggage header on carrier' do
        span = tracer.start_root_span('test')
        ctx = ::OpenTelemetry::Trace.context_with_span(span)

        baggage = Sentry::Baggage.new({
          'trace_id' => 'abc123',
          'public_key' => 'key123'
        })
        ctx = ctx.set_value(described_class::SENTRY_BAGGAGE_KEY, baggage)

        subject.inject(carrier, context: ctx)

        expect(carrier['baggage']).to include('sentry-trace_id=abc123')
        expect(carrier['baggage']).to include('sentry-public_key=key123')
      end

      it 'does not set baggage header when baggage is empty' do
        span = tracer.start_root_span('test')
        ctx = ::OpenTelemetry::Trace.context_with_span(span)

        baggage = Sentry::Baggage.new({})
        ctx = ctx.set_value(described_class::SENTRY_BAGGAGE_KEY, baggage)

        subject.inject(carrier, context: ctx)

        expect(carrier['baggage']).to be_nil
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

    context 'with valid sentry-trace header' do
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

      it 'returns context with correct span_context' do
        updated_ctx = subject.extract(carrier, context: ctx)

        span_context = ::OpenTelemetry::Trace.current_span(updated_ctx).context
        expect(span_context.valid?).to eq(true)
        expect(span_context.hex_trace_id).to eq('d4cda95b652f4a1592b449d5929fda1b')
        expect(span_context.hex_span_id).to eq('6e0c63257de34c92')
        expect(span_context.remote?).to eq(true)
      end
    end

    context 'with sentry-trace and baggage headers' do
      let(:carrier) do
        {
          'sentry-trace' => 'd4cda95b652f4a1592b449d5929fda1b-6e0c63257de34c92-1',
          'baggage' => 'sentry-trace_id=d4cda95b652f4a1592b449d5929fda1b, sentry-public_key=key123'
        }
      end

      it 'returns context with baggage' do
        updated_ctx = subject.extract(carrier, context: ctx)

        baggage = updated_ctx[described_class::SENTRY_BAGGAGE_KEY]
        expect(baggage).to be_a(Sentry::Baggage)
        expect(baggage.mutable).to eq(false)
        expect(baggage.items['trace_id']).to eq('d4cda95b652f4a1592b449d5929fda1b')
        expect(baggage.items['public_key']).to eq('key123')
      end
    end
  end

  describe '#fields' do
    it 'returns header names' do
      expect(subject.fields).to eq(['sentry-trace', 'baggage'])
    end
  end
end
