# frozen_string_literal: true

require 'spec_helper'

return unless defined?(Sidekiq::Cron::Job)

RSpec.describe Sentry::Sidekiq::Cron::Job do
  let(:processor) do
    new_processor
  end

  let(:transport) do
    Sentry.get_current_client.transport
  end

  before do
    perform_basic_setup do |c|
      c.enabled_patches += [:sidekiq_cron]
      c.traces_sample_rate = 1.0
    end
  end

  before do
    Sidekiq::Cron::Job.destroy_all!
    Sidekiq::Queue.all.each(&:clear)
    schedule_file = 'spec/fixtures/sidekiq-cron-schedule.yml'
    schedule = Sidekiq::Cron::Support.load_yaml(ERB.new(IO.read(schedule_file)).result)
    schedule = schedule.merge(symbol_name: { cron: '* * * * *', class: HappyWorkerWithSymbolName })
    # sidekiq-cron 2.0+ accepts second argument to `load_from_hash!` with options,
    # such as {source: 'schedule'}, but sidekiq-cron 1.9.1 (last version to support Ruby 2.6) does not.
    # Since we're not using the source option in our code anyway, it's safe to not pass the 2nd arg.
    Sidekiq::Cron::Job.load_from_hash!(schedule)
  end

  before do
    stub_const('Job', Class.new { include Sidekiq::Worker; def perform; end })
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

  it 'patches HappyWorkerForCron' do
    expect(HappyWorkerForCron.ancestors).to include(Sentry::Cron::MonitorCheckIns)
    expect(HappyWorkerForCron.sentry_monitor_slug).to eq('happy')
    expect(HappyWorkerForCron.sentry_monitor_config).to be_a(Sentry::Cron::MonitorConfig)
    expect(HappyWorkerForCron.sentry_monitor_config.schedule).to be_a(Sentry::Cron::MonitorSchedule::Crontab)
    expect(HappyWorkerForCron.sentry_monitor_config.schedule.value).to eq('* * * * *')
  end

  it 'patches HappyWorkerWithHumanReadableCron' do
    expect(HappyWorkerWithHumanReadableCron.ancestors).to include(Sentry::Cron::MonitorCheckIns)
    expect(HappyWorkerWithHumanReadableCron.sentry_monitor_slug).to eq('human_readable_cron')
    expect(HappyWorkerWithHumanReadableCron.sentry_monitor_config).to be_a(Sentry::Cron::MonitorConfig)
    expect(HappyWorkerWithHumanReadableCron.sentry_monitor_config.schedule).to be_a(Sentry::Cron::MonitorSchedule::Crontab)
    expect(HappyWorkerWithHumanReadableCron.sentry_monitor_config.schedule.value).to eq('*/5 * * * *')
  end

  it 'patches HappyWorkerWithSymbolName' do
    expect(HappyWorkerWithSymbolName.ancestors).to include(Sentry::Cron::MonitorCheckIns)
    expect(HappyWorkerWithSymbolName.sentry_monitor_slug).to eq('symbol_name')
    expect(HappyWorkerWithSymbolName.sentry_monitor_config).to be_a(Sentry::Cron::MonitorConfig)
    expect(HappyWorkerWithSymbolName.sentry_monitor_config.schedule).to be_a(Sentry::Cron::MonitorSchedule::Crontab)
    expect(HappyWorkerWithSymbolName.sentry_monitor_config.schedule.value).to eq('* * * * *')
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

  describe 'sidekiq-cron' do
    it 'adds job to sidekiq within transaction' do
      job = Sidekiq::Cron::Job.new(name: 'test', cron: 'not a crontab', class: 'HappyWorkerForCron')
      job.send(Sentry::Sidekiq::Cron::Job.enqueueing_method)

      expect(::Sidekiq::Queue.new.size).to eq(1)
      expect(transport.events.count).to eq(1)
      event = transport.events.last
      expect(event.spans.count).to eq(1)
      expect(event.spans[0][:op]).to eq("queue.publish")
      expect(event.spans[0][:data]['messaging.destination.name']).to eq('default')
    end

    it 'adds job to sidekiq within transaction' do
      job = Sidekiq::Cron::Job.new(name: 'test', cron: 'not a crontab', class: 'HappyWorkerForCron')
      job.send(Sentry::Sidekiq::Cron::Job.enqueueing_method)
      # Time passes.
      job.send(Sentry::Sidekiq::Cron::Job.enqueueing_method)

      expect(::Sidekiq::Queue.new.size).to eq(2)
      expect(transport.events.count).to eq(2)
      events = transport.events
      expect(events[0].spans.count).to eq(1)
      expect(events[0].spans[0][:op]).to eq("queue.publish")
      expect(events[0].spans[0][:data]['messaging.destination.name']).to eq('default')
      expect(events[1].spans.count).to eq(1)
      expect(events[1].spans[0][:op]).to eq("queue.publish")
      expect(events[1].spans[0][:data]['messaging.destination.name']).to eq('default')

      expect(events[0].dynamic_sampling_context['trace_id']).to_not eq(events[1].dynamic_sampling_context['trace_id'])
    end
  end
end
