# frozen_string_literal: true

require "spec_helper"

begin
  require "good_job"
rescue LoadError
end

if defined?(::GoodJob)
  RSpec.describe Sentry::Rails::GoodJobCron, type: :job do
    include_context "active_job backend harness", adapter: :test
    include_context "test adapter"

    let(:excluded_jobs) { [] }
    let(:configure_sentry) do
      proc do |config|
        config.enabled_patches << :good_job_cron
        config.rails.good_job_exclude_cron_jobs = excluded_jobs
      end
    end

    # Runs jobs from their full serialized payload, like GoodJob does.
    def queue_adapter_for_test
      Rails52FullPayloadTestAdapter.new
    end

    def drain
      jobs = queue_adapter.enqueued_jobs.dup
      queue_adapter.enqueued_jobs.clear
      jobs.each { |payload| ::ActiveJob::Base.execute(payload[:_sentry_full_payload]) }
    end

    def run_entry(key, **params)
      GoodJob::CronEntry.new(params.merge(key: key)).enqueue(Time.now)
      drain
    end

    def check_ins
      sentry_events.select { |event| event.is_a?(Sentry::CheckInEvent) }
    end

    let(:report_job) do
      job_fixture("ReportJob") do
        def perform(*); end
      end
    end

    before { report_job }

    it "sends in_progress and ok check-ins with the cron key and schedule" do
      run_entry(:nightly_report, class: "ReportJob", cron: "0 9 * * 1-5 Europe/Vienna")

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

    it "sends an error check-in when the job fails" do
      job_fixture("FailingReportJob") do
        def perform
          raise "boom"
        end
      end

      expect { run_entry(:failing_report, class: "FailingReportJob", cron: "every hour") }.to raise_error("boom")
      expect(check_ins.map(&:status)).to eq([:in_progress, :error])
      expect(check_ins.first.monitor_config.to_h[:schedule]).to eq(type: :crontab, value: "0 * * * *")
    end

    it "checks in again when a failed run is retried" do
      job_fixture("FlakyReportJob") do
        retry_on RuntimeError, wait: 0, attempts: 2

        def perform
          raise "boom" if executions == 1
        end
      end

      run_entry(:flaky_report, class: "FlakyReportJob", cron: "0 9 * * *")
      drain

      expect(check_ins.map(&:status)).to eq([:in_progress, :error, :in_progress, :ok])
      expect(check_ins.map(&:monitor_slug).uniq).to eq(["flaky_report"])
      expect(check_ins[2].monitor_config.to_h[:schedule]).to eq(type: :crontab, value: "0 9 * * *")
    end

    it "uses each entry's key and schedule when entries share a job class" do
      run_entry(:report_eu, class: "ReportJob", args: ["eu"], cron: "0 9 * * * Europe/Berlin")
      run_entry(:report_us, class: ReportJob, args: ["us"], cron: "0 9 * * * America/New_York")

      in_progress = check_ins.select { |check_in| check_in.status == :in_progress }
      expect(in_progress.map { |check_in| [check_in.monitor_slug, check_in.monitor_config.timezone] }).to eq(
        [["report_eu", "Europe/Berlin"], ["report_us", "America/New_York"]]
      )
    end

    it "uses the zone GoodJob evaluates zoneless schedules in" do
      Time.use_zone("Tokyo") do
        run_entry(:tokyo_report, class: "ReportJob", cron: "0 9 * * *")
      end

      expect(check_ins.first.monitor_config.timezone).to eq("Asia/Tokyo")
    end

    it "sends check-ins without a config for schedules Crons cannot express" do
      run_entry(:every_ten_seconds, class: "ReportJob", cron: "every 10 seconds")

      expect(check_ins.map(&:status)).to eq([:in_progress, :ok])
      expect(check_ins.map(&:monitor_config)).to all(be_nil)
    end

    it "sends check-ins without a config for proc schedules" do
      run_entry(:dynamic_report, class: "ReportJob", cron: ->(_last_ran) { "0 9 * * *" })

      expect(check_ins.map(&:monitor_slug)).to eq(["dynamic_report", "dynamic_report"])
      expect(check_ins.map(&:monitor_config)).to all(be_nil)
    end

    it "leaves jobs that include Sentry::Cron::MonitorCheckIns alone" do
      job_fixture("MonitoredJob") do
        include Sentry::Cron::MonitorCheckIns
        sentry_monitor_check_ins slug: "own-slug"

        def perform; end
      end

      run_entry(:monitored, class: "MonitoredJob", cron: "0 9 * * *")

      expect(check_ins.map(&:monitor_slug)).to eq(["own-slug", "own-slug"])
    end

    it "does not monitor jobs enqueued outside a cron entry" do
      report_job.perform_later
      drain

      expect(check_ins).to be_empty
    end

    it "excludes nothing by default" do
      expect(Sentry.configuration.rails.good_job_exclude_cron_jobs).to eq([])
    end

    context "with excluded jobs" do
      let(:excluded_jobs) { [:clear_cache, "purge", /\Atmp_/] }

      it "skips entries whose key matches a symbol or string" do
        run_entry(:clear_cache, class: "ReportJob", cron: "0 9 * * *")
        run_entry(:purge, class: "ReportJob", cron: "0 9 * * *")

        expect(check_ins).to be_empty
      end

      it "skips entries whose key matches a regexp" do
        run_entry(:tmp_cleanup, class: "ReportJob", cron: "0 9 * * *")

        expect(check_ins).to be_empty
      end

      it "monitors entries that do not match" do
        run_entry(:clear_cache_daily, class: "ReportJob", cron: "0 9 * * *")

        expect(check_ins.map(&:monitor_slug)).to eq(["clear_cache_daily", "clear_cache_daily"])
      end
    end

    context "with an exclusion pattern that raises" do
      let(:excluded_jobs) { [->(_key) { raise "boom" }] }

      it "still enqueues and monitors the job" do
        run_entry(:daily_report, class: "ReportJob", cron: "0 9 * * *")

        expect(check_ins.map(&:monitor_slug)).to eq(["daily_report", "daily_report"])
      end
    end
  end
end
