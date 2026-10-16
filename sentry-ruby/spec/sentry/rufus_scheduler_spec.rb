# frozen_string_literal: true

require "rufus-scheduler"

RSpec.describe Sentry::RufusScheduler do
  let(:scheduler) { Rufus::Scheduler.new }

  before do
    perform_basic_setup do |config|
      config.enabled_patches << :rufus_scheduler
    end
  end

  after do
    scheduler.shutdown(:kill)
  end

  def schedule(type, schedule, **opts, &block)
    block ||= proc { 42 }
    scheduler.send(type, schedule, opts.merge(job: true, first_in: "1h"), &block)
  end

  def monitor_config(type, schedule, **opts)
    schedule(type, schedule, **opts).call(true)
    sentry_events.first.monitor_config&.to_h
  end

  it "sends in_progress and ok check-ins around a cron job" do
    job = schedule(:cron, "0 9 * * 1-5 Europe/Vienna", name: "daily-report")

    expect(job.call(true)).to eq(42)

    in_progress, ok = sentry_events
    expect(sentry_events.count).to eq(2)
    expect(in_progress.monitor_slug).to eq("daily-report")
    expect(in_progress.status).to eq(:in_progress)
    expect(in_progress.monitor_config.to_h).to eq(
      schedule: { type: :crontab, value: "0 9 * * 1-5" },
      timezone: "Europe/Vienna"
    )
    expect(ok.status).to eq(:ok)
    expect(ok.check_in_id).to eq(in_progress.check_in_id)
    expect(ok.duration).to be >= 0
  end

  it "sends an error check-in and still hands the error to rufus" do
    job = schedule(:cron, "0 9 * * *", name: "failing") { raise "boom" }
    expect(scheduler).to receive(:on_error).with(job, an_instance_of(RuntimeError))

    job.call(true)

    expect(sentry_events.map(&:status)).to eq([:in_progress, :error])
  end

  it "re-raises when rufus does not rescue" do
    job = schedule(:cron, "0 9 * * *", name: "failing") { raise "boom" }

    expect { job.call(false) }.to raise_error("boom")
    expect(sentry_events.map(&:status)).to eq([:in_progress, :error])
  end

  it "sends no config for cron lines Crons can't express" do
    expect(monitor_config(:cron, "*/10 * * * * *", name: "job")).to be_nil
    expect(sentry_events.count).to eq(2)
  end

  it "sends an interval config for every jobs" do
    expect(monitor_config(:every, "2h", name: "job")[:schedule]).to eq(type: :interval, value: 2, unit: :hour)
  end

  it "sends check-ins without config for interval jobs" do
    expect(monitor_config(:interval, "5m", name: "job")).to be_nil
    expect(sentry_events.count).to eq(2)
  end

  it "does not monitor one-off jobs" do
    schedule(:in, "1h", name: "job").call(true)
    scheduler.at(Time.now + 3600, name: "job", job: true) { 42 }.call(true)

    expect(sentry_events).to be_empty
  end

  it "does not monitor jobs scheduled with sentry_monitor: false" do
    schedule(:every, "10m", name: "job", sentry_monitor: false).call(true)

    expect(sentry_events).to be_empty
  end

  it "leaves sidekiq-scheduler jobs to the sidekiq_scheduler patch" do
    job = schedule(:every, "10m", name: "job")
    allow(job.callable).to receive(:source_location).and_return(["/gems/sidekiq-scheduler-6.0.2/lib/sidekiq-scheduler/scheduler.rb", 270])

    job.call(true)

    expect(sentry_events).to be_empty
  end

  describe "slug" do
    it "slugifies the job name" do
      schedule(:every, "10m", name: "Nightly Cleanup!").call(true)

      expect(sentry_events.first.monitor_slug).to eq("nightly-cleanup")
    end

    it "uses the handler class name" do
      stub_const("Reports::Handler", Class.new { def call(_job); end })
      scheduler.every("10m", Reports::Handler, job: true, first_in: "1h").call(true)

      expect(sentry_events.first.monitor_slug).to eq("reports-handler")
    end

    it "keeps the first 50 characters of long names" do
      schedule(:every, "10m", name: "#{"a" * 45}-#{"b" * 10}").call(true)

      expect(sentry_events.first.monitor_slug).to eq("#{"a" * 45}-bbbb")
    end

    it "uses the method name for method handlers" do
      handler = Object.new
      def handler.sync_accounts; end
      stub_const("Reports", Module.new { def self.run; end })
      stub_const("Reports::Daily", Class.new { def build; end })

      scheduler.every("10m", handler.method(:sync_accounts), job: true, first_in: "1h").call(true)
      scheduler.every("10m", Reports.method(:run), job: true, first_in: "1h").call(true)
      scheduler.every("10m", Reports::Daily.new.method(:build), job: true, first_in: "1h").call(true)

      expect(sentry_events.map(&:monitor_slug).uniq).to eq(["sync_accounts", "reports-run", "reports-daily-build"])
    end

    it "uses the receiver's class for inherited and mixin methods" do
      stub_const("BaseTask", Class.new { def run; end })
      stub_const("DailyReport", Class.new(BaseTask))
      stub_const("WeeklyReport", Class.new(BaseTask))
      stub_const("Syncable", Module.new { def sync; end })
      stub_const("AccountSync", Class.new { include Syncable })

      scheduler.every("10m", DailyReport.new.method(:run), job: true, first_in: "1h").call(true)
      scheduler.every("10m", WeeklyReport.new.method(:run), job: true, first_in: "1h").call(true)
      scheduler.every("10m", AccountSync.new.method(:sync), job: true, first_in: "1h").call(true)

      expect(sentry_events.map(&:monitor_slug).uniq).to eq(["dailyreport-run", "weeklyreport-run", "accountsync-sync"])
    end

    it "does not monitor unnamed blocks and says to pass a name" do
      string_io = StringIO.new
      Sentry.configuration.sdk_logger = ::Logger.new(string_io)

      job = schedule(:every, "10m") { 42 }
      expect(job.call(true)).to eq(42)
      job.call(true)

      expect(sentry_events).to be_empty
      expect(string_io.string.scan("pass `name:`").size).to eq(1)
    end
  end

  it "runs the job unmonitored when building the monitor fails" do
    string_io = StringIO.new
    Sentry.configuration.sdk_logger = ::Logger.new(string_io)
    allow(Sentry::RufusScheduler).to receive(:monitor_for).and_raise("boom")

    expect(schedule(:cron, "0 9 * * *", name: "job").call(true)).to eq(42)
    expect(sentry_events).to be_empty
    expect(string_io.string).to include("RuntimeError: boom")
  end
end
