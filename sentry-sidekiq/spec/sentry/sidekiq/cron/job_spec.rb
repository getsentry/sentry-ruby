require 'spec_helper'

return unless defined?(Sidekiq::Cron::Job)

RSpec.describe Sentry::Sidekiq::Cron::Job do
  before do
    perform_basic_setup { |c| c.enabled_patches += [:sidekiq_cron] }
  end

  before do
    schedule_file = 'spec/fixtures/schedule.yml'
    schedule = Sidekiq::Cron::Support.load_yaml(ERB.new(IO.read(schedule_file)).result)
    Sidekiq::Cron::Job.load_from_hash!(schedule, source: 'schedule')
  end

  it 'patches class' do
    expect(Sidekiq::Cron::Job.ancestors).to include(described_class)
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

  it 'does not patch ReportingWorker because of invalid schedule' do
    expect(ReportingWorker.ancestors).not_to include(Sentry::Cron::MonitorSchedule)
  end

  it 'does not raise error on invalid class' do
    expect do
      Sidekiq::Cron::Job.create(name: 'invalid_class', cron: '* * * * *', class: 'UndefinedClass')
    end.not_to raise_error
  end

end
