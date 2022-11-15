require 'spec_helper'

RSpec.describe Sentry::OpenTelemetry::SpanProcessor do
  let(:subject) { described_class.instance }
  let(:tracer) { ::OpenTelemetry.tracer_provider.tracer('sentry', '1.0') }

  before do
    perform_basic_setup
    perform_otel_setup
    subject.clear
  end

  describe 'singleton instance' do
    it 'has empty span_map' do
      expect(subject.span_map).to eq({})
    end

    it 'raises error on instantiation' do
      expect { described_class.new }.to raise_error(NoMethodError)
    end
  end

  describe '#on_start' do
    context 'when root span' do
      let(:parent_context) { ::OpenTelemetry::Context.empty }

      let(:root_span) do
        attributes = {
          'http.method' => 'GET',
          'http.host' => 'sentry.io',
          'http.scheme' => 'https'
        }

        tracer.start_root_span('HTTP GET', attributes: attributes, kind: :server)
      end

      let(:invalid_span) { ::OpenTelemetry::SDK::Trace::Span::INVALID }

      it 'noops when not initialized' do
        expect(Sentry).to receive(:initialized?).and_return(false)
        subject.on_start(root_span, parent_context)
        expect(subject.span_map).to eq({})
      end

      it 'noops when instrumenter is not otel' do
        perform_basic_setup do |c|
          c.instrumenter = :sentry
        end

        subject.on_start(root_span, parent_context)
        expect(subject.span_map).to eq({})
      end

      it 'noops when invalid span' do
        subject.on_start(invalid_span, parent_context)
        expect(subject.span_map).to eq({})
      end

      it 'starts a sentry transaction' do
        expect(Sentry).to receive(:start_transaction).and_call_original
        subject.on_start(root_span, parent_context)

        span_id = root_span.context.hex_span_id
        trace_id = root_span.context.hex_trace_id

        expect(subject.span_map.size).to eq(1)
        expect(subject.span_map.keys.first).to eq(span_id)

        transaction = subject.span_map.values.first
        expect(transaction).to be_a(Sentry::Transaction)
        expect(transaction.name).to eq(root_span.name)
        expect(transaction.span_id).to eq(span_id)
        expect(transaction.trace_id).to eq(trace_id)
        expect(transaction.start_timestamp).to eq(root_span.start_timestamp / 1e9)

        expect(transaction.parent_span_id).to eq(nil)
        expect(transaction.parent_sampled).to eq(nil)
        expect(transaction.baggage).to eq(nil)
      end
    end

    context 'when child span' do
      # TODO
      it 'noops on internal sentry sdk requests' do
      end
    end
  end
end
