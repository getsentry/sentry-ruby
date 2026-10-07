# frozen_string_literal: true

require "spec_helper"

if RAILS_VERSION >= 8.1
  require "active_job/continuation/test_helper"

  RSpec.describe "Sentry + ActiveJob::Continuable", type: :job do
    include_context "active_job backend harness", adapter: :test
    include_context "test adapter"
    include ActiveJob::Continuation::TestHelper

    let(:configure_sentry) do
      proc { |config| config.rails.active_job_report_on_retry_error = true }
    end

    let(:performed_steps) { [] }

    def error_events
      sentry_events.reject { |event| event.is_a?(Sentry::TransactionEvent) }
    end

    it "resumes an interrupted job and finishes it" do
      steps = performed_steps
      job = job_fixture do
        include ActiveJob::Continuable

        define_method(:perform) do
          step(:first) { steps << :first }
          step(:second) { steps << :second }
        end
      end

      job.perform_later

      expect do
        interrupt_job_after_step(job, :first) { perform_enqueued_jobs }
        drain
      end.not_to raise_error

      expect(performed_steps).to eq([:first, :second])
      expect(error_events).to be_empty
    end

    it "resumes a job that failed after making progress and finishes it" do
      steps = performed_steps
      failures = ["step two failed once"]
      job = job_fixture do
        include ActiveJob::Continuable

        define_method(:perform) do
          step(:first) { steps << :first }
          step(:second) do
            failure = failures.shift
            raise failure if failure

            steps << :second
          end
        end
      end

      job.perform_later

      expect { drain }.not_to raise_error

      expect(performed_steps).to eq([:first, :second])
    end
  end
end
