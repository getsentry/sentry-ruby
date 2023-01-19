# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Sentry::OpenTelemetry::SpanProcessor do
  let(:subject) { described_class.instance }

  let(:tracer) { ::OpenTelemetry.tracer_provider.tracer('sentry', '1.0') }
  let(:empty_context) { ::OpenTelemetry::Context.empty }
  let(:invalid_span) { ::OpenTelemetry::SDK::Trace::Span::INVALID }

  let(:root_span) do
    attributes = {
      'http.method' => 'GET',
      'http.host' => 'sentry.io',
      'http.scheme' => 'https'
    }

    tracer.start_root_span('HTTP GET', attributes: attributes, kind: :server)
  end

  let(:root_parent_context) do
    ::OpenTelemetry::Trace.context_with_span(root_span, parent_context: empty_context)
  end

  let(:child_db_span) do
    attributes = {
      'db.system' => 'postgresql',
      'db.user' => 'foo',
      'db.name' => 'foo',
      'net.peer.name' => 'localhost',
      'net.transport' => 'IP.TCP',
      'net.peer.ip' => '::1,127.0.0.1',
      'net.peer.port' => '5432,5432',
      'db.operation' => 'SELECT',
      'db.statement' => 'SELECT * FROM foo'
    }

    tracer.start_span('SELECT table', with_parent: root_parent_context, attributes: attributes, kind: :client)
  end

  let(:child_http_span) do
    attributes = {
      'http.method' => 'GET',
      'http.scheme' => 'https',
      'http.target' => '/search',
      'net.peer.name' => 'www.google.com',
      'net.peer.port' => 443,
      'http.status_code' => 200
    }

    tracer.start_span('HTTP GET', with_parent: root_parent_context, attributes: attributes, kind: :client)
  end

  let(:child_internal_span) do
    attributes = {
      'http.method' => 'POST',
      'http.scheme' => 'https',
      'http.target' => '/api/5434472/envelope/',
      'net.peer.name' => 'sentry.localdomain',
      'net.peer.port' => 443
    }

    tracer.start_span('HTTP POST', with_parent: root_parent_context, attributes: attributes, kind: :client)
  end

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

    context 'global event processor' do
      let(:event_processor) { Sentry::Scope.global_event_processors.first }
      let(:event) { Sentry::Event.new(configuration: Sentry.configuration) }
      let(:hint) { {} }

      before { subject.on_start(root_span, empty_context) }

      it 'sets trace context on event' do
        OpenTelemetry::Context.with_current(root_parent_context) do
          event_processor.call(event, hint)
          expect(event.contexts).to include(:trace)
          expect(event.contexts[:trace][:trace_id]).to eq(root_span.context.hex_trace_id)
          expect(event.contexts[:trace][:span_id]).to eq(root_span.context.hex_span_id)
        end
      end
    end
  end

  describe '#on_start' do
    it 'noops when not initialized' do
      expect(Sentry).to receive(:initialized?).and_return(false)
      subject.on_start(root_span, empty_context)
      expect(subject.span_map).to eq({})
    end

    it 'noops when instrumenter is not otel' do
      perform_basic_setup do |c|
        c.instrumenter = :sentry
      end

      subject.on_start(root_span, empty_context)
      expect(subject.span_map).to eq({})
    end

    it 'noops when invalid span' do
      subject.on_start(invalid_span, empty_context)
      expect(subject.span_map).to eq({})
    end

    it 'starts a sentry transaction on otel root span' do
      expect(Sentry).to receive(:start_transaction).and_call_original
      subject.on_start(root_span, empty_context)

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

    context 'with started transaction' do
      let(:transaction) do
        subject.on_start(root_span, empty_context)
        subject.span_map.values.first
      end

      it 'noops on internal sentry sdk requests' do
        expect(transaction).not_to receive(:start_child)
        subject.on_start(child_internal_span, root_parent_context)
      end

      it 'starts a sentry child span on otel child span' do
        expect(transaction).to receive(:start_child).and_call_original
        subject.on_start(child_db_span, root_parent_context)

        span_id = child_db_span.context.hex_span_id
        trace_id = child_db_span.context.hex_trace_id

        expect(subject.span_map.size).to eq(2)
        expect(subject.span_map.keys.last).to eq(span_id)

        sentry_span = subject.span_map[span_id]
        expect(sentry_span).to be_a(Sentry::Span)
        expect(sentry_span.transaction).to eq(transaction)
        expect(sentry_span.span_id).to eq(span_id)
        expect(sentry_span.trace_id).to eq(trace_id)
        expect(sentry_span.description).to eq(child_db_span.name)
        expect(sentry_span.start_timestamp).to eq(child_db_span.start_timestamp / 1e9)
      end
    end
  end

  describe '#on_finish' do
    before do
      subject.on_start(root_span, empty_context)
      subject.on_start(child_db_span, root_parent_context)
      subject.on_start(child_http_span, root_parent_context)
    end

    let(:finished_db_span) { child_db_span.finish }
    let(:finished_http_span) { child_http_span.finish }
    let(:finished_root_span) { root_span.finish }
    let(:finished_invalid_span) { invalid_span.finish }

    it 'noops when not initialized' do
      expect(Sentry).to receive(:initialized?).and_return(false)
      expect(subject.span_map).not_to receive(:delete)
      subject.on_finish(finished_root_span)
    end

    it 'noops when instrumenter is not otel' do
      perform_basic_setup do |c|
        c.instrumenter = :sentry
      end

      expect(subject.span_map).not_to receive(:delete)
      subject.on_finish(finished_root_span)
    end

    it 'noops when invalid span' do
      expect(subject.span_map).not_to receive(:delete)
      subject.on_finish(finished_invalid_span)
    end

    it 'finishes sentry child span on otel child db span finish' do
      expect(subject.span_map).to receive(:delete).and_call_original

      span_id = finished_db_span.context.hex_span_id
      sentry_span = subject.span_map[span_id]
      expect(sentry_span).to be_a(Sentry::Span)

      expect(sentry_span).to receive(:finish).and_call_original
      subject.on_finish(finished_db_span)

      expect(sentry_span.op).to eq('db')
      expect(sentry_span.description).to eq(finished_db_span.attributes['db.statement'])
      expect(sentry_span.data).to include(finished_db_span.attributes)
      expect(sentry_span.data).to include({ 'otel.kind' => finished_db_span.kind })
      expect(sentry_span.timestamp).to eq(finished_db_span.end_timestamp / 1e9)

      expect(subject.span_map.size).to eq(2)
      expect(subject.span_map.keys).not_to include(span_id)
    end

    it 'finishes sentry child span on otel child http span finish' do
      expect(subject.span_map).to receive(:delete).and_call_original

      span_id = finished_http_span.context.hex_span_id
      sentry_span = subject.span_map[span_id]
      expect(sentry_span).to be_a(Sentry::Span)

      expect(sentry_span).to receive(:finish).and_call_original
      subject.on_finish(finished_http_span)

      expect(sentry_span.op).to eq('http.client')
      expect(sentry_span.description).to eq('GET www.google.com/search')
      expect(sentry_span.data).to include(finished_http_span.attributes)
      expect(sentry_span.data).to include({ 'otel.kind' => finished_http_span.kind })
      expect(sentry_span.timestamp).to eq(finished_http_span.end_timestamp / 1e9)
      expect(sentry_span.status).to eq('ok')

      expect(subject.span_map.size).to eq(2)
      expect(subject.span_map.keys).not_to include(span_id)
    end

    it 'finishes sentry transaction on otel root span finish' do
      subject.on_finish(finished_db_span)
      subject.on_finish(finished_http_span)

      expect(subject.span_map).to receive(:delete).and_call_original

      span_id = finished_root_span.context.hex_span_id
      transaction = subject.span_map[span_id]
      expect(transaction).to be_a(Sentry::Transaction)

      expect(transaction).to receive(:finish).and_call_original
      subject.on_finish(finished_root_span)

      expect(transaction.op).to eq('http.server')
      expect(transaction.name).to eq(finished_root_span.name)
      expect(transaction.status).to eq('ok')
      expect(transaction.contexts[:otel]).to eq({
        attributes: finished_root_span.attributes,
        resource: finished_root_span.resource.attribute_enumerator.to_h
      })

      expect(subject.span_map).to eq({})
    end
  end
end
