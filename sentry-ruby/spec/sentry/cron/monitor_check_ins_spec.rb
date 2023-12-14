require 'spec_helper'

RSpec.describe Sentry::Cron::MonitorCheckIns do
  before { perform_basic_setup }

  shared_examples 'original_job' do
    it 'does the work' do
      expect(job).to receive(:work).with(1, 42, 99).and_call_original
      expect(job.perform(1)).to eq(142)
    end

    it 'does the work with args' do
      expect(job).to receive(:work).with(1, 43, 100).and_call_original
      expect(job.perform(1, 43, c: 100)).to eq(144)
    end
  end

  context 'without including mixin' do
    before do
      job_class = Class.new do
        def work(a, b, c); a + b + c end

        def perform(a, b = 42, c: 99)
          work(a, b, c)
        end
      end

      stub_const('Job', job_class)
    end

    let(:job) { Job.new }

    it_behaves_like 'original_job'

    it 'does not call capture_check_in' do
      expect(Sentry).not_to receive(:capture_check_in)
      job.perform(1)
    end
  end

  context 'including mixin' do
    context 'without patching' do
      before do
        mod = described_class

        job_class = Class.new do
          include mod

          def work(a, b, c); a + b + c end

          def perform(a, b = 42, c: 99)
            work(a, b, c)
          end
        end

        stub_const('Job', job_class)
      end

      let(:job) { Job.new }

      it_behaves_like 'original_job'

      it 'does not prepend the patch' do
        expect(Job.ancestors.first).not_to eq(described_class::Patch)
      end

      it 'does not call capture_check_in' do
        expect(Sentry).not_to receive(:capture_check_in)
        job.perform(1)
      end

      it 'class has extended methods' do
        expect(Job.methods).to include(
          :sentry_monitor_check_ins,
          :sentry_monitor_slug,
          :sentry_monitor_config
        )
      end
    end

    context 'patched with default options' do
      before do
        mod = described_class

        job_class = Class.new do
          include mod

          sentry_monitor_check_ins

          def work(a, b, c); a + b + c end

          def perform(a, b = 42, c: 99)
            work(a, b, c)
          end
        end

        stub_const('Job', job_class)
      end

      let(:job) { Job.new }

      it_behaves_like 'original_job'

      it 'prepends the patch' do
        expect(Job.ancestors.first).to eq(described_class::Patch)
      end

      it 'calls capture_check_in twice' do
        expect(Sentry).to receive(:capture_check_in).with(
          'job',
          :in_progress,
          hash_including(monitor_config: nil)
        ).ordered.and_call_original

        expect(Sentry).to receive(:capture_check_in).with(
          'job',
          :ok,
          hash_including(:check_in_id, monitor_config: nil, duration: 0)
        ).ordered.and_call_original

        job.perform(1)
      end
    end

    context 'patched perform with arity 0 with default options' do
      before do
        mod = described_class

        job_class = Class.new do
          include mod
          sentry_monitor_check_ins

          def work; 42 end
          def perform; work end
        end

        stub_const('Job', job_class)
      end

      let(:job) { Job.new }

      it 'prepends the patch' do
        expect(Job.ancestors.first).to eq(described_class::Patch)
      end

      it 'does the work' do
        expect(job).to receive(:work).and_call_original
        expect(job.perform).to eq(42)
      end

      it 'calls capture_check_in twice' do
        expect(Sentry).to receive(:capture_check_in).with(
          'job',
          :in_progress,
          hash_including(monitor_config: nil)
        ).ordered.and_call_original

        expect(Sentry).to receive(:capture_check_in).with(
          'job',
          :ok,
          hash_including(:check_in_id, monitor_config: nil, duration: 0)
        ).ordered.and_call_original

        job.perform(1)
      end
    end

    context 'with very long class name' do
      before do
        mod = described_class

        job_class = Class.new do
          include mod

          sentry_monitor_check_ins

          def work(a, b, c); a + b + c end

          def perform(a, b = 42, c: 99)
            work(a, b, c)
          end
        end

        stub_const('VeryLongOuterModule::VeryVeryVeryVeryLongInnerModule::Job', job_class)
      end

      it 'truncates from the beginning and parameterizes slug' do
        slug = VeryLongOuterModule::VeryVeryVeryVeryLongInnerModule::Job.sentry_monitor_slug
        expect(slug).to eq('ongoutermodule-veryveryveryverylonginnermodule-job')
      end
    end

    context 'patched with custom options' do
      let(:config) { Sentry::Cron::MonitorConfig::from_interval(1, :minute) }

      before do
        mod = described_class
        conf = config

        job_class = Class.new do
          include mod

          sentry_monitor_check_ins slug: 'custom_slug', monitor_config: conf

          def work(a, b, c); a + b + c end

          def perform(a, b = 42, c: 99)
            work(a, b, c)
          end
        end

        stub_const('Job', job_class)
      end

      let(:job) { Job.new }

      it_behaves_like 'original_job'

      it 'prepends the patch' do
        expect(Job.ancestors.first).to eq(described_class::Patch)
      end

      it 'has correct custom options' do
        expect(Job.sentry_monitor_slug).to eq('custom_slug')
        expect(Job.sentry_monitor_config).to eq(config)
      end

      it 'calls capture_check_in twice' do
        expect(Sentry).to receive(:capture_check_in).with(
          'custom_slug',
          :in_progress,
          hash_including(monitor_config: config)
        ).ordered.and_call_original

        expect(Sentry).to receive(:capture_check_in).with(
          'custom_slug',
          :ok,
          hash_including(:check_in_id, monitor_config: config, duration: 0)
        ).ordered.and_call_original

        job.perform(1)
      end
    end

    context 'patched with custom options with exception' do
      let(:config) { Sentry::Cron::MonitorConfig::from_crontab('5 * * * *') }

      before do
        mod = described_class
        conf = config

        job_class = Class.new do
          include mod

          sentry_monitor_check_ins slug: 'custom_slug', monitor_config: conf

          def work(a, b, c);
            1 / 0
          end

          def perform(a, b = 42, c: 99)
            work(a, b, c)
          end
        end

        stub_const('Job', job_class)
      end

      let(:job) { Job.new }

      it 'does the work' do
        expect(job).to receive(:work).with(1, 42, 99).and_call_original
        expect { job.perform(1) }.to raise_error(ZeroDivisionError)
      end

      it 'does the work with args' do
        expect(job).to receive(:work).with(1, 43, 100).and_call_original
        expect { job.perform(1, 43, c: 100) }.to raise_error(ZeroDivisionError)
      end

      it 'prepends the patch' do
        expect(Job.ancestors.first).to eq(described_class::Patch)
      end

      it 'has correct custom options' do
        expect(Job.sentry_monitor_slug).to eq('custom_slug')
        expect(Job.sentry_monitor_config).to eq(config)
      end

      it 'calls capture_check_in twice with error status and re-raises exception' do
        expect(Sentry).to receive(:capture_check_in).with(
          'custom_slug',
          :in_progress,
          hash_including(monitor_config: config)
        ).ordered.and_call_original

        expect(Sentry).to receive(:capture_check_in).with(
          'custom_slug',
          :error,
          hash_including(:check_in_id, monitor_config: config, duration: 0)
        ).ordered.and_call_original

        expect { job.perform(1) }.to raise_error(ZeroDivisionError)
      end
    end
  end
end
