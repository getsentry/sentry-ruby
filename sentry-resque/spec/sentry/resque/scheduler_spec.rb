# frozen_string_literal: true

require "spec_helper"

begin
  require "resque/scheduler"
rescue LoadError
end

if defined?(::Resque::Scheduler)
  Resque::Scheduler.logger = ::Logger.new(nil)

  class ScheduledReportJob
    @queue = :default

    def self.perform(*); end
  end

  class FailingScheduledJob
    @queue = :default

    def self.perform
      raise "boom"
    end
  end

  RSpec.describe Sentry::Resque::Scheduler do
    let(:excluded_jobs) { [] }

    before do
      perform_basic_setup do |config|
        config.enabled_patches << :resque_scheduler
        config.resque.exclude_scheduled_jobs = excluded_jobs
      end
      allow(Resque::Scheduler).to receive(:am_master).and_return(true)
      Resque::Scheduler.clear_schedule!
    end

    after do
      Resque::Scheduler.clear_schedule!
    end

    let(:worker) { Resque::Worker.new(:default) }

    def run_schedule(name, config)
      Resque::Scheduler.load_schedule_job(name, config)
      Resque::Scheduler.scheduled_jobs.fetch(name).callable.call
      worker.work_one_job(worker.reserve)
    end

    def check_ins
      sentry_events.select { |event| event.is_a?(Sentry::CheckInEvent) }
    end

    it "sends in_progress and ok check-ins with the schedule name and cron" do
      run_schedule("nightly_report", "cron" => "0 9 * * 1-5 Europe/Vienna", "class" => "ScheduledReportJob")

      in_progress, ok = check_ins
      expect(check_ins.size).to eq(2)
      expect(in_progress.monitor_slug).to eq("nightly_report")
      expect(in_progress.status).to eq(:in_progress)
      expect(in_progress.monitor_config.to_h).to eq(
        schedule: { type: :crontab, value: "0 9 * * 1-5" },
        timezone: "Europe/Vienna"
      )
      expect(ok.status).to eq(:ok)
      expect(ok.check_in_id).to eq(in_progress.check_in_id)
    end

    it "sends an interval config for every schedules" do
      run_schedule("Hourly Sync", "every" => ["2h", { "first_in" => "1h" }], "class" => "ScheduledReportJob")

      expect(check_ins.map(&:monitor_slug)).to eq(["hourly-sync", "hourly-sync"])
      expect(check_ins.first.monitor_config.to_h[:schedule]).to eq(type: :interval, value: 2, unit: :hour)
    end

    it "strips leading and trailing dashes from the slug" do
      run_schedule("--Hourly Sync!-", "every" => "1h", "class" => "ScheduledReportJob")

      expect(check_ins.map(&:monitor_slug)).to eq(["hourly-sync", "hourly-sync"])
    end

    it "uses the scheduler's local zone for zoneless crons" do
      original = ENV["TZ"]
      ENV["TZ"] = "Asia/Tokyo"
      run_schedule("tokyo_report", "cron" => "0 9 * * *", "class" => "ScheduledReportJob")

      expect(check_ins.first.monitor_config.timezone).to eq("Asia/Tokyo")
    ensure
      ENV["TZ"] = original
    end

    it "sends an error check-in when the job fails" do
      run_schedule("failing", "cron" => "*/15 * * * * UTC", "class" => "FailingScheduledJob")

      expect(check_ins.map(&:status)).to eq([:in_progress, :error])
      expect(check_ins.first.monitor_config.to_h[:schedule]).to eq(type: :crontab, value: "*/15 * * * *")
    end

    it "uses each schedule's name when schedules share a job class" do
      run_schedule("report_eu", "cron" => "0 9 * * * Europe/Berlin", "class" => "ScheduledReportJob", "args" => ["eu"])
      run_schedule("report_us", "cron" => "0 9 * * * America/New_York", "class" => "ScheduledReportJob", "args" => ["us"])

      in_progress = check_ins.select { |check_in| check_in.status == :in_progress }
      expect(in_progress.map { |check_in| [check_in.monitor_slug, check_in.monitor_config.timezone] }).to eq(
        [["report_eu", "Europe/Berlin"], ["report_us", "America/New_York"]]
      )
    end

    it "sends check-ins without a config for schedules Crons cannot express" do
      run_schedule("every_ten_seconds", "every" => "10s", "class" => "ScheduledReportJob")

      expect(check_ins.map(&:status)).to eq([:in_progress, :ok])
      expect(check_ins.map(&:monitor_config)).to all(be_nil)
    end

    it "marks its rufus jobs so the rufus-scheduler patch skips them" do
      Resque::Scheduler.load_schedule_job("nightly_report", "cron" => "0 9 * * *", "class" => "ScheduledReportJob")

      expect(Resque::Scheduler.scheduled_jobs["nightly_report"].opts[:sentry_monitor]).to eq(false)
    end

    it "does not monitor jobs pushed by the scheduled job's enqueue hooks" do
      stub_const("FollowUpJob", Class.new { @queue = :default; def self.perform; end })
      stub_const("HookedScheduledJob", Class.new do
        @queue = :default
        def self.perform; end

        def self.after_enqueue_follow_up(*)
          Resque.enqueue(FollowUpJob)
        end
      end)

      Resque::Scheduler.load_schedule_job("hooked", "cron" => "0 9 * * *", "class" => "HookedScheduledJob")
      Resque::Scheduler.scheduled_jobs.fetch("hooked").callable.call
      2.times { worker.work_one_job(worker.reserve) }

      expect(check_ins.map(&:monitor_slug)).to eq(["hooked", "hooked"])
    end

    it "does not monitor jobs enqueued outside a schedule" do
      Resque.enqueue(ScheduledReportJob)
      worker.work_one_job(worker.reserve)

      expect(check_ins).to be_empty
    end

    it "excludes nothing by default" do
      expect(Sentry.configuration.resque.exclude_scheduled_jobs).to eq([])
    end

    context "with excluded jobs" do
      let(:excluded_jobs) { ["clear_cache", /\Atmp_/] }

      it "skips schedules whose name matches a string or regexp" do
        run_schedule("clear_cache", "cron" => "0 9 * * *", "class" => "ScheduledReportJob")
        run_schedule("tmp_cleanup", "cron" => "0 9 * * *", "class" => "ScheduledReportJob")

        expect(check_ins).to be_empty
      end

      it "monitors schedules that do not match" do
        run_schedule("clear_cache_daily", "cron" => "0 9 * * *", "class" => "ScheduledReportJob")

        expect(check_ins.map(&:monitor_slug)).to eq(["clear_cache_daily", "clear_cache_daily"])
      end
    end

    context "with an exclusion pattern that raises" do
      let(:excluded_jobs) { [->(_name) { raise "boom" }] }

      it "still enqueues and monitors the job" do
        run_schedule("daily_report", "cron" => "0 9 * * *", "class" => "ScheduledReportJob")

        expect(check_ins.map(&:monitor_slug)).to eq(["daily_report", "daily_report"])
      end
    end
  end
end
