require 'spec_helper'

return unless defined?(SidekiqScheduler::Scheduler)

RSpec.describe Sentry::SidekiqScheduler::Scheduler do
  before do
    perform_basic_setup { |c| c.enabled_patches += [:sidekiq_scheduler] }
  end

  before do
    schedule_file = 'spec/fixtures/sidekiq-scheduler-schedule.yml'
    sidekiq_config = ::Sidekiq::Config.new({scheduler: YAML.load_file(schedule_file)})
    
    # Sidekiq::Scheduler merges it's config with Sidekiq.
    # To grab a config for it to start, we need to pass sidekiq configuration 
    # (defaults should be fine though).
    scheduler_config = SidekiqScheduler::Config.new(sidekiq_config: sidekiq_config)

    # Making and starting a Manager instance will load the jobs
    schedule_manager = SidekiqScheduler::Manager.new(scheduler_config)
    schedule_manager.start
  end

  it 'patches class' do
    expect(SidekiqScheduler::Scheduler.ancestors).to include(described_class)
  end

  it 'patches HappyWorker' do
    expect(HappyWorkerDup.ancestors).to include(Sentry::Cron::MonitorCheckIns)
    expect(HappyWorkerDup.sentry_monitor_slug).to eq('happy')
    expect(HappyWorkerDup.sentry_monitor_config).to be_a(Sentry::Cron::MonitorConfig)
    expect(HappyWorkerDup.sentry_monitor_config.schedule).to be_a(Sentry::Cron::MonitorSchedule::Crontab)
    expect(HappyWorkerDup.sentry_monitor_config.schedule.value).to eq('* * * * *')
  end

  it 'does not override SadWorkerWithCron manually set values' do
    expect(SadWorkerWithCron.ancestors).to include(Sentry::Cron::MonitorCheckIns)
    expect(SadWorkerWithCron.sentry_monitor_slug).to eq('failed_job')
    expect(SadWorkerWithCron.sentry_monitor_config).to be_a(Sentry::Cron::MonitorConfig)
    expect(SadWorkerWithCron.sentry_monitor_config.schedule).to be_a(Sentry::Cron::MonitorSchedule::Crontab)
    expect(SadWorkerWithCron.sentry_monitor_config.schedule.value).to eq('5 * * * *')
  end
end

