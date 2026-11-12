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
    let(:cron) { {} }
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

    around do |example|
      configuration = GoodJob.configuration
      GoodJob.configuration = GoodJob::Configuration.new({ cron: cron })
      example.run
    ensure
      GoodJob.configuration = configuration
    end

    def run_entry(key, **params)
      cron[key] = params unless params.empty?
      GoodJob::CronEntry.find(key).enqueue(Time.now)
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
      expect(ok.monitor_config).to be_nil
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
      expect(check_ins.last.monitor_config).to be_nil
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

    context "with an app time zone" do
      around do |example|
        zone_default = Time.zone_default
        tz = ENV.delete("TZ")
        Time.zone_default = Time.find_zone!("Asia/Tokyo")
        example.run
      ensure
        Time.zone_default = zone_default
        ENV["TZ"] = tz
      end

      it "uses it for zoneless schedules, whatever zone the enqueue runs in" do
        Time.use_zone("America/Chicago") do
          run_entry(:tokyo_report, class: "ReportJob", cron: "0 9 * * *")
        end

        expect(check_ins.first.monitor_config.timezone).to eq("Asia/Tokyo")
      end
    end

    it "skips schedules Crons cannot express" do
      run_entry(:every_ten_seconds, class: "ReportJob", cron: "every 10 seconds")

      expect(check_ins).to be_empty
    end

    it "skips proc schedules" do
      run_entry(:dynamic_report, class: "ReportJob", cron: ->(_last_ran) { "0 9 * * *" })

      expect(check_ins).to be_empty
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

    it "monitors jobs that include Sentry::Cron::MonitorCheckIns without configuring it" do
      job_fixture("UnconfiguredJob") do
        include Sentry::Cron::MonitorCheckIns

        def perform; end
      end

      run_entry(:unconfigured, class: "UnconfiguredJob", cron: "0 9 * * *")

      expect(check_ins.map(&:monitor_slug)).to eq(["unconfigured", "unconfigured"])
    end

    it "monitors entries whose class is callable" do
      skip "GoodJob #{GoodJob::VERSION} has no callable classes" if Gem::Version.new(GoodJob::VERSION) < Gem::Version.new("4.19.3")

      run_entry(:callable_report, class: -> { ReportJob }, cron: "0 9 * * *")

      expect(check_ins.map(&:monitor_slug)).to eq(["callable_report", "callable_report"])
    end

    it "does not monitor other jobs enqueued while an entry enqueues" do
      job_fixture("AuditJob") do
        def perform; end
      end
      job_fixture("AuditedReportJob") do
        before_enqueue { AuditJob.perform_later }

        def perform; end
      end

      run_entry(:audited_report, class: "AuditedReportJob", cron: "0 9 * * *")

      expect(check_ins.map(&:monitor_slug)).to eq(["audited_report", "audited_report"])
    end

    it "still enqueues the job when monitoring it fails" do
      string_io = StringIO.new
      Sentry.configuration.sdk_logger = ::Logger.new(string_io)

      # find raises for an entry missing from GoodJob's configuration.
      GoodJob::CronEntry.new(key: :unlisted_report, class: "ReportJob", cron: "0 9 * * *").enqueue(Time.now)

      expect(queue_adapter.enqueued_jobs.size).to eq(1)
      drain
      expect(check_ins).to be_empty
      expect(string_io.string).to include("Not monitoring GoodJob cron entry unlisted_report")
    end

    context "when GoodJob runs jobs inline" do
      # GoodJob's inline mode runs the job inside the cron enqueue and resets its thread state first.
      def queue_adapter_for_test
        Class.new(::ActiveJob::QueueAdapters::TestAdapter) do
          def enqueue(job)
            payload = job.serialize
            ::GoodJob::CurrentThread.within do |thread|
              thread.reset
              ::ActiveJob::Base.execute(payload)
            end
          end

          def enqueue_at(job, _timestamp)
            enqueue(job)
          end
        end.new
      end

      it "does not monitor a job the cron job enqueues of its own class" do
        job_fixture("ChainedReportJob") do
          def perform(again = true)
            self.class.perform_later(false) if again
          end
        end

        run_entry(:chained_report, class: "ChainedReportJob", cron: "0 9 * * *")

        expect(check_ins.map(&:status)).to eq([:in_progress, :ok])
      end
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

    context "with cron keys that share a slug" do
      let(:long_key) { "sync_salesforce_accounts_with_the_billing_provider" }
      let(:cron) do
        {
          "#{long_key}_daily": { class: "ReportJob", cron: "0 9 * * *" },
          "#{long_key}_weekly": { class: "ReportJob", cron: "0 9 * * 1" },
          nightly_report: { class: "ReportJob", cron: "0 2 * * *" }
        }
      end

      it "skips all of them and warns" do
        string_io = StringIO.new
        Sentry.configuration.sdk_logger = ::Logger.new(string_io)

        run_entry(:"#{long_key}_daily")
        run_entry(:"#{long_key}_weekly")
        run_entry(:nightly_report)

        expect(check_ins.map(&:monitor_slug).uniq).to eq(["nightly_report"])
        expect(string_io.string).to include("Not monitoring GoodJob cron entry #{long_key}_daily", "#{long_key}_weekly")
      end

      context "when the others sharing its slug aren't monitored" do
        let(:excluded_jobs) { [:"#{long_key}_weekly"] }
        let(:cron) do
          {
            "#{long_key}_daily": { class: "ReportJob", cron: "0 9 * * *" },
            "#{long_key}_weekly": { class: "ReportJob", cron: "0 9 * * 1" },
            "#{long_key}_fast": { class: "ReportJob", cron: "every 10 seconds" },
            "#{long_key}_dynamic": { class: "ReportJob", cron: ->(_last_ran) { "0 9 * * *" } },
            "#{long_key}_self": { class: "SelfMonitoredJob", cron: "0 9 * * *" }
          }
        end

        before do
          job_fixture("SelfMonitoredJob") do
            include Sentry::Cron::MonitorCheckIns
            sentry_monitor_check_ins slug: "self-monitored"

            def perform; end
          end
        end

        it "monitors it and doesn't warn about the others" do
          string_io = StringIO.new
          Sentry.configuration.sdk_logger = ::Logger.new(string_io)

          run_entry(:"#{long_key}_daily")
          run_entry(:"#{long_key}_fast")

          expect(check_ins.map(&:monitor_slug)).to eq([long_key, long_key])
          expect(string_io.string).not_to include("Rename or exclude")
        end
      end

      context "when one of them is excluded" do
        let(:excluded_jobs) { [:"#{long_key}_weekly"] }

        it "monitors the other" do
          run_entry(:"#{long_key}_daily")

          expect(check_ins.map(&:monitor_slug).uniq).to eq([long_key])
        end
      end
    end

    context "with no excluded jobs set" do
      let(:excluded_jobs) { nil }

      it "monitors the entry" do
        run_entry(:daily_report, class: "ReportJob", cron: "0 9 * * *")

        expect(check_ins.map(&:monitor_slug)).to eq(["daily_report", "daily_report"])
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

  if RAILS_VERSION >= 7.1
    RSpec.describe "Sentry::Rails::GoodJobCron on a GoodJob database", type: :job do
      include_context "active_job backend harness", adapter: :good_job
      include_context "good_job database"

      let(:cron) { {} }
      let(:configure_sentry) do
        proc { |config| config.enabled_patches << :good_job_cron }
      end

      def queue_adapter_for_test
        @queue_adapter_for_test ||= ::ActiveJob::QueueAdapters::GoodJobAdapter.new(execution_mode: :external)
      end

      def boot_adapter(_adapter)
        Sentry::Rails::Test::GoodJobDatabase.connect
      end

      def reset_adapter(_adapter)
        GoodJob::Execution.delete_all
        GoodJob::Job.delete_all
      end

      around do |example|
        configuration = GoodJob.configuration
        GoodJob.configuration = GoodJob::Configuration.new({ cron: cron })
        example.run
      ensure
        GoodJob.configuration = configuration
      end

      def drain
        lock_id = SecureRandom.uuid

        loop do
          result = GoodJob::Job.perform_with_advisory_lock(lock_id: lock_id)
          break if result.nil?
          raise result.unhandled_error if result.unhandled_error
        end
      end

      def run_entry(key, at: Time.now.change(usec: 0), **params)
        cron[key] = params unless params.empty?
        GoodJob::CronEntry.find(key).enqueue(at)
        drain
      end

      def check_ins
        sentry_events.select { |event| event.is_a?(Sentry::CheckInEvent) }
      end

      it "sends no check-ins for an overlapping run that GoodJob's concurrency limit rejects" do
        overlapping_run = method(:run_entry)
        overlapping_at = 1.hour.from_now.change(usec: 0)
        job_fixture("ExclusiveReportJob") do
          include GoodJob::ActiveJobExtensions::Concurrency
          self.good_job_labels = ["exclusive_report"]
          good_job_concurrency_rule(label: "exclusive_report", perform_limit: 1)

          define_method(:perform) do
            Thread.new { overlapping_run.call(:exclusive_report, at: overlapping_at) }.join
          end
        end

        run_entry(:exclusive_report, class: "ExclusiveReportJob", cron: "0 * * * * UTC")

        expect(GoodJob::Execution.where("error LIKE ?", "%ConcurrencyExceededError%")).to exist
        expect(check_ins.map(&:status)).to eq([:in_progress, :ok, :in_progress, :ok])
      end
    end
  end
end
