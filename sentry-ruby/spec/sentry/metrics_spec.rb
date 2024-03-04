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
      described_class.timing('foo', unit: 'ratio') { }
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

      described_class.timing('foo', unit: 'millisecond', tags: { fortytwo: 42 }, timestamp: fake_time) { sleep(0.1) }
    end
  end
end
