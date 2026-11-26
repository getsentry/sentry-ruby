# frozen_string_literal: true

require "spec_helper"

begin
  require "good_job"
rescue LoadError
end

if defined?(::GoodJob)
  RSpec.describe "GoodJob cron notification subscriber", type: :job, isolate: :group do
    include_context "active_job backend harness", adapter: :test
    include_context "test adapter"

    let(:configure_sentry) { proc { |config| config.enabled_patches << :good_job_cron } }
    let(:record) { Struct.new(:cron_key, :job_class).new("report", "ReportJob") }

    around do |example|
      configuration = GoodJob.configuration
      GoodJob.configuration = GoodJob::Configuration.new({ cron: { report: { class: "ReportJob", cron: "0 9 * * *" } } })
      example.run
    ensure
      GoodJob.configuration = configuration
    end

    before { job_fixture("ReportJob") { def perform; end } }

    def check_ins
      sentry_events.grep(Sentry::CheckInEvent)
    end

    def instrument(payload = {}, &block)
      ActiveSupport::Notifications.instrument("perform_job.good_job", { job: record }.merge(payload), &block)
    end

    it "keeps nested executions independent and removes state when they finish" do
      outer_payload = inner_payload = nil
      instrument do |outer|
        outer_payload = outer
        instrument { |inner| inner_payload = inner }
      end

      expect(check_ins.map(&:status)).to eq([:in_progress, :in_progress, :ok, :ok])
      expect(check_ins[0].check_in_id).to eq(check_ins[3].check_in_id)
      expect(check_ins[1].check_in_id).to eq(check_ins[2].check_in_id)
      expect(check_ins[0].check_in_id).not_to eq(check_ins[1].check_in_id)
      expect(outer_payload).not_to have_key(Sentry::Rails::GoodJobCron::EVENT_STATE)
      expect(inner_payload).not_to have_key(Sentry::Rails::GoodJobCron::EVENT_STATE)
    end

    [:handled_error, :unhandled_error].each do |error_key|
      it "reports #{error_key} from GoodJob's result payload" do
        instrument { |payload| payload[error_key] = RuntimeError.new("boom") }

        expect(check_ins.map(&:status)).to eq([:in_progress, :error])
      end
    end

    it "reports exceptions that escape the instrumented execution without swallowing them" do
      expect { instrument { raise "boom" } }.to raise_error("boom")

      expect(check_ins.map(&:status)).to eq([:in_progress, :error])
    end

    it "does not send check-ins for ordinary jobs" do
      record.cron_key = nil
      instrument { }

      expect(check_ins).to be_empty
    end

    it "does not send check-ins when the patch is disabled in a later configuration" do
      Sentry.configuration.enabled_patches.delete(:good_job_cron)
      instrument { }

      expect(check_ins).to be_empty
    end

    it "registers only once when initialized repeatedly" do
      2.times { Sentry::Rails::GoodJobCron.patch }
      instrument { }

      expect(check_ins.map(&:status)).to eq([:in_progress, :ok])
    end
  end
end
