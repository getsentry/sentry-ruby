# frozen_string_literal: true

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
        expect(string_io.string).to include("[#{described_class.name}] thread creation failed")
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

    describe 'with before_emit callback' do
      before do
        perform_basic_setup do |config|
          config.metrics.enabled = true
          config.enable_tracing = true
          config.release = 'test-release'
          config.environment = 'test'
          config.logger = Logger.new(string_io)

          config.metrics.before_emit = lambda do |key, tags|
            return nil if key == 'foo'
            tags[:add_tag] = 42
            tags.delete(:remove_tag)
            true
          end
        end
      end

      it 'does not emit metric with filtered key' do
        expect(Sentry::Metrics::CounterMetric).not_to receive(:new)
        subject.add(:c, 'foo', 1)
        expect(subject.buckets).to eq({})
      end

      it 'updates the tags according to the callback' do
        subject.add(:c, 'bar', 1, tags: { remove_tag: 99 })
        _, _, _, tags = subject.buckets.values.first.keys.first
        expect(tags).not_to include(['remove_tag', '99'])
        expect(tags).to include(['add_tag', '42'])
      end
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

    describe 'code location reporting' do
      it 'does not record location if off' do
        perform_basic_setup do |config|
          config.metrics.enabled = true
          config.metrics.enable_code_locations = false
        end

        subject.add(:c, 'incr', 1)
        expect(subject.code_locations).to eq({})
      end

      it 'records the code location with a timestamp for the day' do
        subject.add(:c, 'incr', 1, unit: 'second', stacklevel: 3)

        timestamp = Time.now.utc
        start_of_day = Time.utc(timestamp.year, timestamp.month, timestamp.day).to_i
        expect(subject.code_locations.keys.first).to eq(start_of_day)
      end

      it 'has the code location keyed with mri (metric resource identifier) from type/key/unit'  do
        subject.add(:c, 'incr', 1, unit: 'second', stacklevel: 3)
        mri = subject.code_locations.values.first.keys.first
        expect(mri).to eq([:c, 'incr', 'second'])
      end

      it 'has the code location information in the hash' do
        subject.add(:c, 'incr', 1, unit: 'second', stacklevel: 3)

        location = subject.code_locations.values.first.values.first
        expect(location).to include(:abs_path, :filename, :pre_context, :context_line, :post_context, :lineno)
        expect(location[:abs_path]).to match(/aggregator_spec.rb/)
        expect(location[:filename]).to match(/aggregator_spec.rb/)
        expect(location[:context_line]).to include("subject.add(:c, 'incr', 1, unit: 'second', stacklevel: 3)")
      end

      it 'does not add code location for the same mri twice' do
        subject.add(:c, 'incr', 1, unit: 'second', stacklevel: 3)
        subject.add(:c, 'incr', 1, unit: 'second', stacklevel: 3)
        expect(subject.code_locations.values.first.size).to eq(1)
      end

      it 'adds code location for different mris twice' do
        subject.add(:c, 'incr', 1, unit: 'second', stacklevel: 3)
        subject.add(:c, 'incr', 1, unit: 'none', stacklevel: 3)
        expect(subject.code_locations.values.first.size).to eq(2)
      end
    end
  end

  describe '#flush' do
    context 'with empty buckets and empty locations' do
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
        5.times { |i| subject.add(:d, 'disöt', i, unit: 'second', tags: { "foö$-bar" => "snöwmän% 23{}" }) }

        allow(Time).to receive(:now).and_return(fake_time + 9)
        5.times { subject.add(:c, 'incr', 1) }
        5.times { |i| subject.add(:d, 'disöt', i + 5, unit: 'second', tags: { "foö$-bar" => "snöwmän% 23{}" }) }

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

        it 'empties the pending code locations in place' do
          subject.flush
          expect(subject.code_locations).to eq({})
        end

        it 'captures the envelope' do
          expect(subject.client).to receive(:capture_envelope)
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
          expect(dist).to eq("dis_t@second:0.0:1.0:2.0:3.0:4.0|d|" +
                             "#environment:test,fo-bar:snöwmän% 23{},release:test-release|" +
                             "T#{fake_time.to_i - 3}")
        end

        it 'sends the pending code locations in metric_meta envelope item with correct payload' do
          subject.flush

          envelope = sentry_envelopes.first
          expect(envelope.headers).to eq({})

          item = envelope.items.last
          expect(item.headers).to eq({ type: 'metric_meta', content_type: 'application/json' })
          expect(item.payload[:timestamp]).to be_a(Integer)

          mapping = item.payload[:mapping]
          expect(mapping.keys).to eq(['c:incr@none', 'd:dis_t@second'])

          location_1 = mapping['c:incr@none'].first
          expect(location_1[:type]).to eq('location')
          expect(location_1).to include(:abs_path, :filename, :lineno)

          location_2 = mapping['d:dis_t@second'].first
          expect(location_2[:type]).to eq('location')
          expect(location_2).to include(:abs_path, :filename, :lineno)
        end
      end

      context 'with force' do
        it 'empties the pending buckets in place' do
          subject.flush(force: true)
          expect(subject.buckets).to eq({})
        end

        it 'captures the envelope' do
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
          expect(dist1).to eq("dis_t@second:0.0:1.0:2.0:3.0:4.0|d|" +
                             "#environment:test,fo-bar:snöwmän% 23{},release:test-release|" +
                             "T#{fake_time.to_i - 3}")
          expect(incr2).to eq("incr@none:5.0|c|#environment:test,release:test-release|T#{fake_time.to_i + 7}")
          expect(dist2).to eq("dis_t@second:5.0:6.0:7.0:8.0:9.0|d|" +
                             "#environment:test,fo-bar:snöwmän% 23{},release:test-release|" +
                             "T#{fake_time.to_i + 7}")
        end
      end
    end

    context 'sanitization' do
      it 'sanitizes the metric key' do
        subject.add(:c, 'foo.disöt_12-bar', 1)
        subject.flush(force: true)

        sanitized_key = 'foo.dis_t_12-bar'
        statsd, metrics_meta = sentry_envelopes.first.items.map(&:payload)
        expect(statsd).to include(sanitized_key)
        expect(metrics_meta[:mapping].keys.first).to include(sanitized_key)
      end

      it 'sanitizes the metric unit' do
        subject.add(:c, 'incr', 1, unit: 'disöt_12-/.test')
        subject.flush(force: true)

        sanitized_unit = '@dist_12test'
        statsd, metrics_meta = sentry_envelopes.first.items.map(&:payload)
        expect(statsd).to include(sanitized_unit)
        expect(metrics_meta[:mapping].keys.first).to include(sanitized_unit)
      end

      it 'sanitizes tag keys and values' do
        tags = { "get.foö-$bar/12" => "hello!\n\r\t\\ 42 this | or , that" }
        subject.add(:c, 'incr', 1, tags: tags)
        subject.flush(force: true)

        sanitized_tags = "get.fo-bar/12:hello!\\n\\r\\t\\\\ 42 this \\u{7c} or \\u{2c} that"
        statsd = sentry_envelopes.first.items.first.payload
        expect(statsd).to include(sanitized_tags)
      end
    end
  end

  describe '#kill' do
    before { subject.add(:c, 'incr', 1) }
    it 'logs message when killing the thread' do
      expect(subject.thread).to receive(:kill)
      subject.kill
      expect(string_io.string).to include("[#{described_class.name}] thread killed")
    end
  end
end
