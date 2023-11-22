require 'spec_helper'

return unless defined?(SidekiqScheduler::Scheduler)

RSpec.describe Sentry::SidekiqScheduler::Scheduler do
  before do
    perform_basic_setup { |c| c.enabled_patches += [:sidekiq_scheduler] }
  end

  before do
    schedule_file = 'spec/fixtures/sidekiq-scheduler-schedule.yml'
    config_options = {scheduler: YAML.load_file(schedule_file)}

    # Sidekiq 7 has a Config class, but for Sidekiq 6, we'll mock it.
    sidekiq_config = if WITH_SIDEKIQ_7
      ::Sidekiq::Config.new(config_options)
    else
      class SidekiqConfigMock
        include ::Sidekiq
        attr_accessor :options
        
        def initialize(options = {})
          @options = DEFAULTS.merge(options)
        end

        def fetch(key, default = nil)
          options.fetch(key, default)
        end

        def [](key)
          options[key]
        end
      end
      SidekiqConfigMock.new(config_options)
    end
    
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

  it "sets correct monitor config based on `every` schedule" do
    expect(EveryHappyWorker.ancestors).to include(Sentry::Cron::MonitorCheckIns)
    expect(EveryHappyWorker.sentry_monitor_slug).to eq('regularly_happy')
    expect(EveryHappyWorker.sentry_monitor_config).to be_a(Sentry::Cron::MonitorConfig)
    expect(EveryHappyWorker.sentry_monitor_config.schedule).to be_a(Sentry::Cron::MonitorSchedule::Interval)
    expect(EveryHappyWorker.sentry_monitor_config.schedule.to_hash).to eq({value: 10.0, type: :interval, unit: :minute})
  end

  it "does not add monitors for a one-off job" do
    expect(ReportingWorker.ancestors).not_to include(Sentry::Cron::MonitorCheckIns)
  end 
end

