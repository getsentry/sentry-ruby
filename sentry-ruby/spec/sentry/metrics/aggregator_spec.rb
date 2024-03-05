require 'spec_helper'

RSpec.describe Sentry::Metrics::Aggregator do
  let(:string_io) { StringIO.new }

  # fix at 3 second offset to check rollup
  let(:fake_time) { Time.new(2024, 1, 1, 1, 1, 3) }

  before do
    perform_basic_setup do |config|
      config.metrics.enabled = true
      config.enable_tracing = true
      config.release = 'test-release'
      config.environment = 'test'
      config.logger = Logger.new(string_io)
    end
  end

  subject { Sentry.metrics_aggregator }

  describe '#add' do
    it 'spawns new thread' do
      expect { subject.add(:c, 'incr', 1) }.to change { Thread.list.count }.by(1)
      expect(subject.thread).to be_a(Thread)
    end

    it 'spawns only one thread' do
      expect { subject.add(:c, 'incr', 1) }.to change { Thread.list.count }.by(1)

      expect(subject.thread).to receive(:alive?).and_call_original
      expect { subject.add(:c, 'incr', 1) }.to change { Thread.list.count }.by(0)
    end

    context 'when thread creation fails' do
      before do
        expect(Thread).to receive(:new).and_raise(ThreadError)
      end

      it 'does not create new thread' do
        expect { subject.add(:c, 'incr', 1) }.to change { Thread.list.count }.by(0)
      end

      it 'noops' do
        subject.add(:c, 'incr', 1)
        expect(subject.buckets).to eq({})
      end

      it 'logs error' do
        subject.add(:c, 'incr', 1)
        expect(string_io.string).to match(/\[Metrics::Aggregator\] thread creation failed/)
      end
    end

    context 'when killed' do
      before { subject.kill }

      it 'noops' do
        subject.add(:c, 'incr', 1)
        expect(subject.buckets).to eq({})
      end

      it 'does not create new thread' do
        expect(Thread).not_to receive(:new)
        expect { subject.add(:c, 'incr', 1) }.to change { Thread.list.count }.by(0)
      end
    end

    it 'does not add unsupported metric type' do
      subject.add(:foo, 'foo', 1)
      expect(subject.buckets).to eq({})
    end

    it 'has the correct bucket timestamp key rolled up to 10 seconds' do
      allow(Time).to receive(:now).and_return(fake_time)
      subject.add(:c, 'incr', 1)
      expect(subject.buckets.keys.first).to eq(fake_time.to_i - 3)
    end

    it 'has the correct bucket timestamp key rolled up to 10 seconds when passed explicitly' do
      subject.add(:c, 'incr', 1, timestamp: fake_time + 9)
      expect(subject.buckets.keys.first).to eq(fake_time.to_i + 7)
    end

    it 'has the correct type in the bucket metric key' do
      subject.add(:c, 'incr', 1)
      type, _, _, _ = subject.buckets.values.first.keys.first
      expect(type).to eq(:c)
    end

    it 'has the correct key in the bucket metric key' do
      subject.add(:c, 'incr', 1)
      _, key, _, _ = subject.buckets.values.first.keys.first
      expect(key).to eq('incr')
    end

    it 'has the default unit \'none\' in the bucket metric key' do
      subject.add(:c, 'incr', 1)
      _, _, unit, _ = subject.buckets.values.first.keys.first
      expect(unit).to eq('none')
    end

    it 'has the correct custom unit in the bucket metric key' do
      subject.add(:c, 'incr', 1, unit: 'second')
      _, _, unit, _ = subject.buckets.values.first.keys.first
      expect(unit).to eq('second')
    end

    it 'has the correct default tags serialized in the bucket metric key' do
      subject.add(:c, 'incr', 1)
      _, _, _, tags = subject.buckets.values.first.keys.first
      expect(tags).to eq([['environment', 'test'], ['release', 'test-release']])
    end

    it 'has the correct custom tags serialized in the bucket metric key' do
      subject.add(:c, 'incr', 1, tags: { foo: 42 })
      _, _, _, tags = subject.buckets.values.first.keys.first
      expect(tags).to include(['foo', '42'])
    end

    it 'has the correct array value tags serialized in the bucket metric key' do
      subject.add(:c, 'incr', 1, tags: { foo: [42, 43] })
      _, _, _, tags = subject.buckets.values.first.keys.first
      expect(tags).to include(['foo', '42'], ['foo', '43'])
    end

    context 'with running transaction' do
      it 'has the transaction name in tags serialized in the bucket metric key' do
        Sentry.get_current_scope.set_transaction_name('foo')
        subject.add(:c, 'incr', 1)
        _, _, _, tags = subject.buckets.values.first.keys.first
        expect(tags).to include(['transaction', 'foo'])
      end

      it 'does not has the low quality transaction name in tags serialized in the bucket metric key' do
        Sentry.get_current_scope.set_transaction_name('foo', source: :url)
        subject.add(:c, 'incr', 1)
        _, _, _, tags = subject.buckets.values.first.keys.first
        expect(tags).not_to include(['transaction', 'foo'])
      end
    end

    it 'creates a new CounterMetric instance if not existing' do
      expect(Sentry::Metrics::CounterMetric).to receive(:new).and_call_original
      subject.add(:c, 'incr', 1)

      metric = subject.buckets.values.first.values.first
      expect(metric).to be_a(Sentry::Metrics::CounterMetric)
      expect(metric.value).to eq(1.0)
    end

    it 'reuses the existing CounterMetric instance' do
      allow(Time).to receive(:now).and_return(fake_time)

      subject.add(:c, 'incr', 1)
      metric = subject.buckets.values.first.values.first
      expect(metric.value).to eq(1.0)

      expect(Sentry::Metrics::CounterMetric).not_to receive(:new)
      expect(metric).to receive(:add).with(2).and_call_original
      subject.add(:c, 'incr', 2)
      expect(metric.value).to eq(3.0)
    end

    it 'creates a new DistributionMetric instance if not existing' do
      expect(Sentry::Metrics::DistributionMetric).to receive(:new).and_call_original
      subject.add(:d, 'dist', 1)

      metric = subject.buckets.values.first.values.first
      expect(metric).to be_a(Sentry::Metrics::DistributionMetric)
      expect(metric.value).to eq([1.0])
    end

    it 'creates a new GaugeMetric instance if not existing' do
      expect(Sentry::Metrics::GaugeMetric).to receive(:new).and_call_original
      subject.add(:g, 'gauge', 1)

      metric = subject.buckets.values.first.values.first
      expect(metric).to be_a(Sentry::Metrics::GaugeMetric)
      expect(metric.serialize).to eq([1.0, 1.0, 1.0, 1.0, 1])
    end

    it 'creates a new SetMetric instance if not existing' do
      expect(Sentry::Metrics::SetMetric).to receive(:new).and_call_original
      subject.add(:s, 'set', 1)

      metric = subject.buckets.values.first.values.first
      expect(metric).to be_a(Sentry::Metrics::SetMetric)
      expect(metric.value).to eq(Set[1])
    end

    describe 'local aggregation for span metric summaries' do
      it 'does nothing without an active scope span' do
        expect_any_instance_of(Sentry::Metrics::LocalAggregator).not_to receive(:add)
        subject.add(:c, 'incr', 1)
      end

      context 'with running transaction and active span' do
        let(:span) { Sentry.start_transaction }

        before do
          Sentry.get_current_scope.set_span(span)
          Sentry.get_current_scope.set_transaction_name('metric', source: :view)
        end

        it 'does nothing if transaction name is low quality' do
          expect_any_instance_of(Sentry::Metrics::LocalAggregator).not_to receive(:add)

          Sentry.get_current_scope.set_transaction_name('/123', source: :url)
          subject.add(:c, 'incr', 1)
        end

        it 'proxies bucket key and value to local aggregator' do
          expect(span.metrics_local_aggregator).to receive(:add).with(
            array_including(:c, 'incr', 'none'),
            1
          )
          subject.add(:c, 'incr', 1)
        end

        context 'for set metrics' do
          before { subject.add(:s, 'set', 'foo') }

          it 'proxies bucket key and value 0 when existing element' do
            expect(span.metrics_local_aggregator).to receive(:add).with(
              array_including(:s, 'set', 'none'),
              0
            )
            subject.add(:s, 'set', 'foo')
          end

          it 'proxies bucket key and value 1 when new element' do
            expect(span.metrics_local_aggregator).to receive(:add).with(
              array_including(:s, 'set', 'none'),
              1
            )
            subject.add(:s, 'set', 'bar')
          end
        end
      end
    end
  end

  describe '#flush' do
    context 'with empty buckets' do
      it 'returns early and does nothing' do
        expect(sentry_envelopes.count).to eq(0)
        subject.flush
      end

      it 'returns early and does nothing with force' do
        expect(sentry_envelopes.count).to eq(0)
        subject.flush(force: true)
      end
    end

    context 'with pending buckets' do
      before do
        allow(Time).to receive(:now).and_return(fake_time)
        10.times { subject.add(:c, 'incr', 1) }
        5.times { |i| subject.add(:d, 'dist', i, unit: 'second', tags: { "foö$-bar" => "snöwmän% 23{}" }) }

        allow(Time).to receive(:now).and_return(fake_time + 9)
        5.times { subject.add(:c, 'incr', 1) }
        5.times { |i| subject.add(:d, 'dist', i + 5, unit: 'second', tags: { "foö$-bar" => "snöwmän% 23{}" }) }

        expect(subject.buckets.keys).to eq([fake_time.to_i - 3, fake_time.to_i + 7])
        expect(subject.buckets.values[0].length).to eq(2)
        expect(subject.buckets.values[1].length).to eq(2)

        # set the time such that the first set of metrics above are picked
        allow(Time).to receive(:now).and_return(fake_time + 9 + subject.flush_shift)
      end

      context 'without force' do
        it 'updates the pending buckets in place' do
          subject.flush

          expect(subject.buckets.keys).to eq([fake_time.to_i + 7])
          expect(subject.buckets.values[0].length).to eq(2)
        end

        it 'calls the background worker' do
          expect(Sentry.background_worker).to receive(:perform)
          subject.flush
        end

        it 'sends the flushable buckets in statsd envelope item with correct payload' do
          subject.flush

          envelope = sentry_envelopes.first
          expect(envelope.headers).to eq({})

          item = envelope.items.first
          expect(item.headers).to eq({ type: 'statsd', length: item.payload.bytesize })

          incr, dist = item.payload.split("\n")
          expect(incr).to eq("incr@none:10.0|c|#environment:test,release:test-release|T#{fake_time.to_i - 3}")
          expect(dist).to eq("dist@second:0.0:1.0:2.0:3.0:4.0|d|" +
                             "#environment:test,fo_-bar:snöwmän 23{},release:test-release|" +
                             "T#{fake_time.to_i - 3}")
        end
      end

      context 'with force' do
        it 'empties the pending buckets in place' do
          subject.flush(force: true)
          expect(subject.buckets).to eq({})
        end

        it 'calls the background worker' do
          expect(Sentry.background_worker).to receive(:perform)
          subject.flush(force: true)
        end

        it 'sends all buckets in statsd envelope item with correct payload' do
          subject.flush(force: true)

          envelope = sentry_envelopes.first
          expect(envelope.headers).to eq({})

          item = envelope.items.first
          expect(item.headers).to eq({ type: 'statsd', length: item.payload.bytesize })

          incr1, dist1, incr2, dist2 = item.payload.split("\n")
          expect(incr1).to eq("incr@none:10.0|c|#environment:test,release:test-release|T#{fake_time.to_i - 3}")
          expect(dist1).to eq("dist@second:0.0:1.0:2.0:3.0:4.0|d|" +
                             "#environment:test,fo_-bar:snöwmän 23{},release:test-release|" +
                             "T#{fake_time.to_i - 3}")
          expect(incr2).to eq("incr@none:5.0|c|#environment:test,release:test-release|T#{fake_time.to_i + 7}")
          expect(dist2).to eq("dist@second:5.0:6.0:7.0:8.0:9.0|d|" +
                             "#environment:test,fo_-bar:snöwmän 23{},release:test-release|" +
                             "T#{fake_time.to_i + 7}")
        end
      end
    end
  end

  describe '#kill' do
    before { subject.add(:c, 'incr', 1) }
    it 'logs message when killing the thread' do
      expect(subject.thread).to receive(:kill)
      subject.kill
      expect(string_io.string).to match(/\[Metrics::Aggregator\] killing thread/)
    end
  end
end
