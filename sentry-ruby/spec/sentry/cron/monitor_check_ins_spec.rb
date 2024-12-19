# frozen_string_literal: true

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
      job.perform(1)

      expect(sentry_events.count).to eq(0)
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

      it 'records 2 check-in events' do
        job.perform(1)

        expect(sentry_events.count).to eq(2)
        in_progress_event = sentry_events.first

        expect(in_progress_event.monitor_slug).to eq('job')
        expect(in_progress_event.status).to eq(:in_progress)
        expect(in_progress_event.monitor_config).to be_nil

        ok_event = sentry_events.last

        expect(ok_event.monitor_slug).to eq('job')
        expect(ok_event.status).to eq(:ok)
        expect(ok_event.monitor_config).to be_nil
        expect(ok_event.duration).to be > 0
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

      it 'records 2 check-in events' do
        expect(job.perform(1)).to eq(42)

        expect(sentry_events.count).to eq(2)
        in_progress_event = sentry_events.first

        expect(in_progress_event.monitor_slug).to eq('job')
        expect(in_progress_event.status).to eq(:in_progress)
        expect(in_progress_event.monitor_config).to be_nil

        ok_event = sentry_events.last

        expect(ok_event.monitor_slug).to eq('job')
        expect(ok_event.status).to eq(:ok)
        expect(ok_event.monitor_config).to be_nil
        expect(ok_event.duration).to be > 0
      end
    end

    context 'with very long class name' do
      before do
        mod = described_class

        job_class = Class.new do
          include mod

          sentry_monitor_check_ins

          def perform
          end
        end

        stub_const('VeryLongOuterModule::VeryVeryVeryVeryLongInnerModule::Job', job_class)
      end

      it 'truncates from the beginning and parameterizes slug' do
        slug = VeryLongOuterModule::VeryVeryVeryVeryLongInnerModule::Job.sentry_monitor_slug
        expect(slug).to eq('ongoutermodule-veryveryveryverylonginnermodule-job')
      end
    end

    context 'patched with monitor config' do
      let(:monitor_config) { Sentry::Cron::MonitorConfig.from_interval(1, :minute) }

      before do
        mod = described_class
        config = monitor_config

        job_class = Class.new do
          include mod

          sentry_monitor_check_ins slug: 'custom_slug', monitor_config: config

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
        expect(Job.sentry_monitor_config).to eq(monitor_config)
      end

      it 'records 2 check-in events' do
        job.perform(1)

        expect(sentry_events.count).to eq(2)
        in_progress_event = sentry_events.first

        expect(in_progress_event.monitor_slug).to eq('custom_slug')
        expect(in_progress_event.status).to eq(:in_progress)
        expect(in_progress_event.monitor_config).to eq(monitor_config)
        expect(in_progress_event.monitor_config.checkin_margin).to eq(nil)
        expect(in_progress_event.monitor_config.max_runtime).to eq(nil)
        expect(in_progress_event.monitor_config.timezone).to eq(nil)

        ok_event = sentry_events.last

        expect(ok_event.monitor_slug).to eq('custom_slug')
        expect(ok_event.status).to eq(:ok)
        expect(ok_event.monitor_config).to eq(monitor_config)
      end
    end

    context 'with custom monitor config object and cron configs' do
      let(:monitor_config) { Sentry::Cron::MonitorConfig.from_interval(1, :minute) }

      before do
        perform_basic_setup do |config|
          config.cron.default_checkin_margin = 10
          config.cron.default_max_runtime = 20
          config.cron.default_timezone = 'Europe/Vienna'
        end

        mod = described_class
        config = monitor_config

        job_class = Class.new do
          include mod

          sentry_monitor_check_ins slug: 'custom_slug', monitor_config: config

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
        expect(Job.sentry_monitor_config).to eq(monitor_config)
      end

      it 'records 2 check-in events' do
        job.perform(1)

        expect(sentry_events.count).to eq(2)
        in_progress_event = sentry_events.first

        expect(in_progress_event.monitor_slug).to eq('custom_slug')
        expect(in_progress_event.status).to eq(:in_progress)
        expect(in_progress_event.monitor_config.checkin_margin).to eq(10)
        expect(in_progress_event.monitor_config.max_runtime).to eq(20)
        expect(in_progress_event.monitor_config.timezone).to eq('Europe/Vienna')

        ok_event = sentry_events.last

        expect(ok_event.monitor_slug).to eq('custom_slug')
        expect(ok_event.status).to eq(:ok)
        expect(ok_event.monitor_config.checkin_margin).to eq(10)
        expect(ok_event.monitor_config.max_runtime).to eq(20)
        expect(ok_event.monitor_config.timezone).to eq('Europe/Vienna')
      end
    end

    context 'patched with custom options with exception' do
      let(:monitor_config) { Sentry::Cron::MonitorConfig.from_crontab('5 * * * *') }

      before do
        mod = described_class
        config = monitor_config

        job_class = Class.new do
          include mod

          sentry_monitor_check_ins slug: 'custom_slug', monitor_config: config

          def work(a, b, c)
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
        expect(Job.sentry_monitor_config).to eq(monitor_config)
      end

      it 'calls capture_check_in twice with error status and re-raises exception' do
        expect { job.perform(1) }.to raise_error(ZeroDivisionError)

        expect(sentry_events.count).to eq(2)
        in_progress_event = sentry_events.first

        expect(in_progress_event.monitor_slug).to eq('custom_slug')
        expect(in_progress_event.status).to eq(:in_progress)
        expect(in_progress_event.monitor_config).to eq(monitor_config)

        error_event = sentry_events.last

        expect(error_event.monitor_slug).to eq('custom_slug')
        expect(error_event.status).to eq(:error)
        expect(error_event.monitor_config).to eq(monitor_config)
      end
    end
  end
end
