# frozen_string_literal: true

require 'spec_helper'
require 'sidekiq/api'

return unless defined?(SidekiqScheduler::Scheduler)

RSpec.describe Sentry::SidekiqScheduler::Scheduler do
  before do
    perform_basic_setup do |c|
      c.enabled_patches += [:sidekiq_scheduler]
      c.traces_sample_rate = 1.0
    end
  end

  before do
    schedule_file = 'spec/fixtures/sidekiq-scheduler-schedule.yml'
    config_options = { scheduler: YAML.load_file(schedule_file) }

    # Sidekiq::Scheduler merges it's config with Sidekiq.
    # To grab a config for it to start, we need to pass sidekiq configuration
    # (defaults should be fine though).
    scheduler_config = SidekiqScheduler::Config.new(sidekiq_config: sidekiq_config(config_options))

    # Making and starting a Manager instance will load the jobs
    @schedule_manager = SidekiqScheduler::Manager.new(scheduler_config)
    @schedule_manager.start
  end

  after do
    @schedule_manager&.stop
  end

  it 'patches class' do
    expect(SidekiqScheduler::Scheduler.ancestors).to include(described_class)
  end

  it 'patches HappyWorkerForScheduler' do
    expect(HappyWorkerForScheduler.ancestors).to include(Sentry::Cron::MonitorCheckIns)
    expect(HappyWorkerForScheduler.sentry_monitor_slug).to eq('happy')
    expect(HappyWorkerForScheduler.sentry_monitor_config).to be_a(Sentry::Cron::MonitorConfig)
    expect(HappyWorkerForScheduler.sentry_monitor_config.schedule).to be_a(Sentry::Cron::MonitorSchedule::Crontab)
    expect(HappyWorkerForScheduler.sentry_monitor_config.schedule.value).to eq('* * * * *')
  end

  it 'patches HappyWorkerForSchedulerWithTimezoneWithTimezone' do
    expect(HappyWorkerForSchedulerWithTimezone.ancestors).to include(Sentry::Cron::MonitorCheckIns)
    expect(HappyWorkerForSchedulerWithTimezone.sentry_monitor_slug).to eq('happy_timezone')
    expect(HappyWorkerForSchedulerWithTimezone.sentry_monitor_config).to be_a(Sentry::Cron::MonitorConfig)
    expect(HappyWorkerForSchedulerWithTimezone.sentry_monitor_config.schedule).to be_a(Sentry::Cron::MonitorSchedule::Crontab)
    expect(HappyWorkerForSchedulerWithTimezone.sentry_monitor_config.schedule.value).to eq('* * * * *')
    expect(HappyWorkerForSchedulerWithTimezone.sentry_monitor_config.timezone).to eq('Europe/Vienna')
  end

  it 'does not override SadWorkerWithCron manually set values' do
    expect(SadWorkerWithCron.ancestors).to include(Sentry::Cron::MonitorCheckIns)
    expect(SadWorkerWithCron.sentry_monitor_slug).to eq('failed_job')
    expect(SadWorkerWithCron.sentry_monitor_config).to be_a(Sentry::Cron::MonitorConfig)
    expect(SadWorkerWithCron.sentry_monitor_config.schedule).to be_a(Sentry::Cron::MonitorSchedule::Crontab)
    expect(SadWorkerWithCron.sentry_monitor_config.schedule.value).to eq('5 * * * *')
  end

  it "sets correct monitor config based on `every` schedule" do
    expect(EveryHappyWorker.ancestors).to include(Sentry::Cron::MonitorCheckIns)
    expect(EveryHappyWorker.sentry_monitor_slug).to eq('regularly_happy')
    expect(EveryHappyWorker.sentry_monitor_config).to be_a(Sentry::Cron::MonitorConfig)
    expect(EveryHappyWorker.sentry_monitor_config.schedule).to be_a(Sentry::Cron::MonitorSchedule::Interval)
    expect(EveryHappyWorker.sentry_monitor_config.schedule.to_h).to eq({ value: 10, type: :interval, unit: :minute })
  end

  it "does not add monitors for a one-off job" do
    expect(ReportingWorker.ancestors).not_to include(Sentry::Cron::MonitorCheckIns)
  end

 it 'truncates from the beginning and parameterizes slug' do
    expect(VeryLongOuterModule::VeryVeryVeryVeryLongInnerModule::Job.ancestors).to include(Sentry::Cron::MonitorCheckIns)
    expect(VeryLongOuterModule::VeryVeryVeryVeryLongInnerModule::Job.sentry_monitor_slug).to eq('ongoutermodule-veryveryveryverylonginnermodule-job')
    expect(VeryLongOuterModule::VeryVeryVeryVeryLongInnerModule::Job.sentry_monitor_config).to be_a(Sentry::Cron::MonitorConfig)
    expect(VeryLongOuterModule::VeryVeryVeryVeryLongInnerModule::Job.sentry_monitor_config.schedule).to be_a(Sentry::Cron::MonitorSchedule::Crontab)
    expect(VeryLongOuterModule::VeryVeryVeryVeryLongInnerModule::Job.sentry_monitor_config.schedule.value).to eq('* * * * *')
 end

  describe '#enqueue_job' do
    let(:transport) { Sentry.get_current_client.transport }
    let(:scheduler) { SidekiqScheduler::Scheduler.instance }

    before do
      Sidekiq::Queue.all.each(&:clear)
    end

    it 'adds job to sidekiq within transaction' do
      scheduler.enqueue_job({ 'class' => 'HappyWorkerForScheduler' })

      expect(::Sidekiq::Queue.new.size).to eq(1)
      expect(transport.events.count).to eq(1)

      transaction = transport.events.last
      expect(transaction.transaction).to eq('HappyWorkerForScheduler')
      expect(transaction.contexts.dig(:trace, :op)).to eq('queue.sidekiq-scheduler')
      expect(transaction.contexts.dig(:trace, :origin)).to eq('auto.queue.sidekiq.scheduler')

      span = transaction.spans.detect { |span| span[:op] == 'queue.publish' }
      expect(span).not_to be_nil
      expect(span[:data]['messaging.destination.name']).to eq('default')
    end

    it 'starts a new trace for each enqueue' do
      scheduler.enqueue_job({ 'class' => 'HappyWorkerForScheduler' })
      scheduler.enqueue_job({ 'class' => 'HappyWorkerForScheduler' })

      events = transport.events
      expect(events.count).to eq(2)
      expect(events[0].dynamic_sampling_context['trace_id']).not_to eq(events[1].dynamic_sampling_context['trace_id'])

      jobs = ::Sidekiq::Queue.new.map(&:item)
      trace_ids = jobs.map { |job| job.dig('trace_propagation_headers', 'sentry-trace').split('-').first }
      sample_rands = jobs.map { |job| job.dig('trace_propagation_headers', 'baggage')[/sentry-sample_rand=([^,]+)/, 1] }

      expect(trace_ids).to match_array(events.map { |event| event.dynamic_sampling_context['trace_id'] })
      expect(sample_rands.uniq.size).to eq(2)
    end
  end
end
