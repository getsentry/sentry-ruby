require 'spec_helper'

return unless defined?(Sidekiq::Cron::Job)

RSpec.describe Sentry::Sidekiq::Cron::Job do
  before do
    perform_basic_setup { |c| c.enabled_patches += [:sidekiq_cron] }
  end

  before do
    schedule_file = 'spec/fixtures/schedule.yml'
    schedule = Sidekiq::Cron::Support.load_yaml(ERB.new(IO.read(schedule_file)).result)
    # sidekiq-cron 2.0+ accepts second argument to `load_from_hash!` with options,
    # such as {source: 'schedule'}, but sidekiq-cron 1.9.1 (last version to support Ruby 2.6) does not.
    # Since we're not using the source option in our code anyway, it's safe to not pass the 2nd arg.
    Sidekiq::Cron::Job.load_from_hash!(schedule)
  end

  before do
    stub_const('Job', Class.new { def perform; end })
  end

  it 'patches class' do
    expect(Sidekiq::Cron::Job.ancestors).to include(described_class)
  end

  it 'preserves return value' do
    job = Sidekiq::Cron::Job.new(name: 'test', cron: '* * * * *', class: 'Job')
    expect(job.save).to eq(true)
  end

  it 'preserves return value in invalid case' do
    job = Sidekiq::Cron::Job.new(name: 'test', cron: 'not a crontab', class: 'Job')
    expect(job.save).to eq(false)
  end

  it 'does not raise error on invalid class' do
    expect do
      Sidekiq::Cron::Job.create(name: 'invalid_class', cron: '* * * * *', class: 'UndefinedClass')
    end.not_to raise_error
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
end
