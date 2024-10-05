# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Sentry::Metrics::LocalAggregator do
  let(:tags) { [['foo', 1], ['foo', 2], ['bar', 'baz']] }
  let(:key) { [:c, 'incr', 'second', tags] }
  let(:key2) { [:s, 'set', 'none', []] }

  describe '#add' do
    it 'creates new GaugeMetric and adds it to bucket if key not existing' do
      expect(Sentry::Metrics::GaugeMetric).to receive(:new).with(10).and_call_original

      subject.add(key, 10)

      metric = subject.buckets[key]
      expect(metric).to be_a(Sentry::Metrics::GaugeMetric)
      expect(metric.last).to eq(10.0)
      expect(metric.min).to eq(10.0)
      expect(metric.max).to eq(10.0)
      expect(metric.sum).to eq(10.0)
      expect(metric.count).to eq(1)
    end

    it 'adds value to existing GaugeMetric' do
      subject.add(key, 10)

      metric = subject.buckets[key]
      expect(metric).to be_a(Sentry::Metrics::GaugeMetric)
      expect(metric).to receive(:add).with(20).and_call_original
      expect(Sentry::Metrics::GaugeMetric).not_to receive(:new)

      subject.add(key, 20)
      expect(metric.last).to eq(20.0)
      expect(metric.min).to eq(10.0)
      expect(metric.max).to eq(20.0)
      expect(metric.sum).to eq(30.0)
      expect(metric.count).to eq(2)
    end
  end

  describe '#to_hash' do
    it 'returns nil if empty buckets' do
      expect(subject.to_hash).to eq(nil)
    end

    context 'with filled buckets' do
      before do
        subject.add(key, 10)
        subject.add(key, 20)
        subject.add(key2, 1)
      end

      it 'has the correct payload keys in the hash' do
        expect(subject.to_hash.keys).to eq([
          'c:incr@second',
          's:set@none'
        ])
      end

      it 'has the tags deserialized correctly with array values' do
        expect(subject.to_hash['c:incr@second'][:tags]).to eq({
          'foo' => [1, 2],
          'bar' => 'baz'
        })
      end

      it 'has the correct gauge metric values' do
        expect(subject.to_hash['c:incr@second']).to include({
          min: 10.0,
          max: 20.0,
          count: 2,
          sum: 30.0
        })

        expect(subject.to_hash['s:set@none']).to include({
          min: 1.0,
          max: 1.0,
          count: 1,
          sum: 1.0
        })
      end
    end
  end
end
