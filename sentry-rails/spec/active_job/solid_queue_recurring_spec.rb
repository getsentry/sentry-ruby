# frozen_string_literal: true

require "spec_helper"

if RAILS_VERSION >= 7.1 && RUBY_VERSION >= "3.1"
  require "solid_queue"

  SOLID_QUEUE_RECURRING_ADAPTER = ::ActiveJob::QueueAdapters::SolidQueueAdapter.new

  RSpec.describe Sentry::Rails::SolidQueueRecurring, type: :job do
    include_context "active_job backend harness", adapter: :solid_queue

    let(:configure_sentry) { proc { |config| config.enabled_patches << :solid_queue_recurring } }

    def queue_adapter_for_test
      SOLID_QUEUE_RECURRING_ADAPTER
    end

    def boot_adapter(_adapter)
      Sentry::Rails::Test::Application.load_queue_schema
    end

    def reset_adapter(_adapter)
      [
        SolidQueue::ReadyExecution,
        SolidQueue::ClaimedExecution,
        SolidQueue::FailedExecution,
        SolidQueue::ScheduledExecution,
        SolidQueue::RecurringExecution,
        SolidQueue::Process,
        SolidQueue::Job
      ].each(&:delete_all)
    end

    def drain
      process = SolidQueue::Process.register(kind: "Worker", pid: ::Process.pid, name: "spec-#{SecureRandom.hex(4)}")
      SolidQueue::ReadyExecution.claim("*", 100, process.id).each(&:perform)
    end

    def run_task(key, **options)
      SolidQueue::RecurringTask.from_configuration(key, **options).enqueue(at: Time.now.change(usec: 0))
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

    it "sends in_progress and ok check-ins with the task key and schedule" do
      run_task("nightly_report", class: "ReportJob", schedule: "0 9 * * 1-5 Europe/Vienna")

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

      expect { run_task("failing_report", class: "FailingReportJob", schedule: "every hour") }.to raise_error("boom")
      expect(check_ins.map(&:status)).to eq([:in_progress, :error])
      expect(check_ins.first.monitor_config.to_h[:schedule]).to eq(type: :crontab, value: "0 * * * *")
    end

    it "uses each task's key and schedule when tasks share a job class" do
      run_task("report_eu", class: "ReportJob", args: ["eu"], schedule: "0 9 * * * Europe/Berlin")
      run_task("report_us", class: "ReportJob", args: ["us"], schedule: "0 9 * * * America/New_York")

      in_progress = check_ins.select { |check_in| check_in.status == :in_progress }
      expect(in_progress.map { |check_in| [check_in.monitor_slug, check_in.monitor_config.timezone] }).to eq(
        [["report_eu", "Europe/Berlin"], ["report_us", "America/New_York"]]
      )
    end

    it "monitors command tasks" do
      run_task("Cleanup Cache", command: "1 + 1", schedule: "*/15 * * * * UTC")

      expect(check_ins.map(&:monitor_slug)).to eq(["cleanup-cache", "cleanup-cache"])
      expect(check_ins.first.monitor_config.to_h[:schedule]).to eq(type: :crontab, value: "*/15 * * * *")
    end

    it "sends check-ins without a config for schedules Sentry would read differently" do
      run_task("month_end", class: "ReportJob", schedule: "0 12 L * *")

      expect(check_ins.map(&:status)).to eq([:in_progress, :ok])
      expect(check_ins.map(&:monitor_config)).to all(be_nil)
    end

    it "applies SolidQueue.time_zone to schedules without a zone" do
      skip "SolidQueue.time_zone is not supported" unless SolidQueue.respond_to?(:time_zone=)

      original = SolidQueue.time_zone
      SolidQueue.time_zone = "Tokyo"
      run_task("tokyo_report", class: "ReportJob", schedule: "0 9 * * *")

      expect(check_ins.first.monitor_config.timezone).to eq("Asia/Tokyo")
    ensure
      SolidQueue.time_zone = original if SolidQueue.respond_to?(:time_zone=)
    end

    it "leaves jobs that include Sentry::Cron::MonitorCheckIns alone" do
      job_fixture("MonitoredJob") do
        include Sentry::Cron::MonitorCheckIns
        sentry_monitor_check_ins slug: "own-slug"

        def perform; end
      end

      run_task("monitored", class: "MonitoredJob", schedule: "0 9 * * *")

      expect(check_ins.map(&:monitor_slug)).to eq(["own-slug", "own-slug"])
    end

    it "monitors jobs that include Sentry::Cron::MonitorCheckIns without configuring it" do
      job_fixture("UnconfiguredJob") do
        include Sentry::Cron::MonitorCheckIns

        def perform; end
      end

      run_task("unconfigured", class: "::UnconfiguredJob", schedule: "0 9 * * *")

      expect(check_ins.map(&:monitor_slug)).to eq(["unconfigured", "unconfigured"])
    end

    it "does not monitor jobs enqueued outside a recurring task" do
      report_job.perform_later
      drain

      expect(check_ins).to be_empty
    end
  end
end
