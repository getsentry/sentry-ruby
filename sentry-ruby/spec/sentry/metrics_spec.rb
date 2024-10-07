# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Sentry::Metrics do
  before do
    perform_basic_setup do |config|
      config.metrics.enabled = true
    end
  end

  let(:aggregator) { Sentry.metrics_aggregator }
  let(:fake_time) { Time.new(2024, 1, 1, 1, 1, 3) }

  describe '.increment' do
    it 'passes default value of 1.0 with only key' do
      expect(aggregator).to receive(:add).with(
        :c,
        'foo',
        1.0,
        unit: 'none',
        tags: {},
        timestamp: nil
      )

      described_class.increment('foo')
    end

    it 'passes through args to aggregator' do
      expect(aggregator).to receive(:add).with(
        :c,
        'foo',
        5.0,
        unit: 'second',
        tags: { fortytwo: 42 },
        timestamp: fake_time
      )

      described_class.increment('foo', 5.0, unit: 'second', tags: { fortytwo: 42 }, timestamp: fake_time)
    end
  end

  describe '.distribution' do
    it 'passes through args to aggregator' do
      expect(aggregator).to receive(:add).with(
        :d,
        'foo',
        5.0,
        unit: 'second',
        tags: { fortytwo: 42 },
        timestamp: fake_time
      )

      described_class.distribution('foo', 5.0, unit: 'second', tags: { fortytwo: 42 }, timestamp: fake_time)
    end
  end

  describe '.set' do
    it 'passes through args to aggregator' do
      expect(aggregator).to receive(:add).with(
        :s,
        'foo',
        'jane',
        unit: 'none',
        tags: { fortytwo: 42 },
        timestamp: fake_time
      )

      described_class.set('foo', 'jane', tags: { fortytwo: 42 }, timestamp: fake_time)
    end
  end

  describe '.gauge' do
    it 'passes through args to aggregator' do
      expect(aggregator).to receive(:add).with(
        :g,
        'foo',
        5.0,
        unit: 'second',
        tags: { fortytwo: 42 },
        timestamp: fake_time
      )

      described_class.gauge('foo', 5.0, unit: 'second', tags: { fortytwo: 42 }, timestamp: fake_time)
    end
  end

  describe '.timing' do
    it 'does nothing without a block' do
      expect(aggregator).not_to receive(:add)
      described_class.timing('foo')
    end

    it 'does nothing with a non-duration unit' do
      expect(aggregator).not_to receive(:add)
      result = described_class.timing('foo', unit: 'ratio') { 42 }
      expect(result).to eq(42)
    end

    it 'measures time taken as distribution and passes through args to aggregator' do
      expect(aggregator).to receive(:add).with(
        :d,
        'foo',
        an_instance_of(Integer),
        unit: 'millisecond',
        tags: { fortytwo: 42 },
        timestamp: fake_time
      )

      result = described_class.timing('foo', unit: 'millisecond', tags: { fortytwo: 42 }, timestamp: fake_time) { sleep(0.1); 42 }
      expect(result).to eq(42)
    end

    context 'with running transaction' do
      let(:transaction) { transaction = Sentry.start_transaction(name: 'metrics') }

      before do
        perform_basic_setup do |config|
          config.enable_tracing = true
          config.metrics.enabled = true
        end

        Sentry.get_current_scope.set_span(transaction)
      end

      it 'starts a span' do
        expect(Sentry).to receive(:with_child_span).with(op: Sentry::Metrics::OP_NAME, description: 'foo', origin: Sentry::Metrics::SPAN_ORIGIN).and_call_original

        described_class.timing('foo') { sleep(0.1) }
      end

      it 'has the correct tags on the new span' do
        described_class.timing('foo', tags: { a: 42, b: [1, 2] }) { sleep(0.1) }
        span = transaction.span_recorder.spans.last
        expect(span.tags).to eq(a: '42', b: '1, 2')
      end
    end
  end
end
