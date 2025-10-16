# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sentry::GoodJob::ErrorHandler do
  before do
    perform_basic_setup
  end

  let(:handler) { described_class.new }
  let(:transport) { Sentry.get_current_client.transport }

  describe "#call" do
    let(:job) { double("Job", class: job_class, job_id: "123", queue_name: "default", executions: 1, enqueued_at: Time.now, scheduled_at: nil, arguments: []) }
    let(:job_class) { double("JobClass", retry_on_attempts: nil, name: "TestJob") }
    let(:exception) { build_exception }

    context "when Sentry is not initialized" do
      before do
        allow(Sentry).to receive(:initialized?).and_return(false)
      end

      it "does not capture the exception" do
        expect(Sentry::GoodJob).not_to receive(:capture_exception)
        handler.call(exception, job)
      end
    end

    context "when Sentry is initialized" do
      before do
        allow(Sentry).to receive(:initialized?).and_return(true)
      end

      it "captures the exception with correct context" do
        expect(Sentry::GoodJob).to receive(:capture_exception).with(
          exception,
          contexts: { good_job: hash_including(
            job_class: "TestJob",
            job_id: "123",
            queue_name: "default",
            executions: 1
          ) },
          hint: { background: true }
        )

        handler.call(exception, job)
      end

      context "when include_job_arguments is enabled" do
        before do
          Sentry.configuration.good_job.include_job_arguments = true
        end

        it "includes job arguments in context" do
          expect(Sentry::GoodJob).to receive(:capture_exception).with(
            exception,
            contexts: { good_job: hash_including(arguments: []) },
            hint: { background: true }
          )

          handler.call(exception, job)
        end
      end

      context "when report_after_job_retries is enabled" do
        before do
          Sentry.configuration.good_job.report_after_job_retries = true
        end

        context "and job is retryable" do
          let(:job_class) { double("JobClass", retry_on_attempts: 3, name: "TestJob") }

          context "and retry count is less than max retries" do
            let(:job) { double("Job", class: job_class, job_id: "123", queue_name: "default", executions: 2, enqueued_at: Time.now, scheduled_at: nil, arguments: []) }

            it "does not capture the exception" do
              expect(Sentry::GoodJob).not_to receive(:capture_exception)
              handler.call(exception, job)
            end
          end

          context "and retry count equals max retries" do
            let(:job) { double("Job", class: job_class, job_id: "123", queue_name: "default", executions: 3, enqueued_at: Time.now, scheduled_at: nil, arguments: []) }

            it "captures the exception" do
              expect(Sentry::GoodJob).to receive(:capture_exception)
              handler.call(exception, job)
            end
          end
        end

        context "and job is not retryable" do
          let(:job_class) { double("JobClass", retry_on_attempts: nil, name: "TestJob") }

          it "captures the exception" do
            expect(Sentry::GoodJob).to receive(:capture_exception)
            handler.call(exception, job)
          end
        end
      end

      context "when report_only_dead_jobs is enabled" do
        before do
          Sentry.configuration.good_job.report_only_dead_jobs = true
        end

        context "and job is retryable" do
          let(:job_class) { double("JobClass", retry_on_attempts: 3, name: "TestJob") }

          it "does not capture the exception" do
            expect(Sentry::GoodJob).not_to receive(:capture_exception)
            handler.call(exception, job)
          end
        end

        context "and job is not retryable" do
          let(:job_class) { double("JobClass", retry_on_attempts: nil, name: "TestJob") }

          it "captures the exception" do
            expect(Sentry::GoodJob).to receive(:capture_exception)
            handler.call(exception, job)
          end
        end
      end
    end
  end

  describe "#retryable?" do
    it "returns true when job has retry_on_attempts" do
      job_class = double("JobClass", retry_on_attempts: 3)
      job = double("Job", class: job_class)

      expect(handler.send(:retryable?, job)).to be true
    end

    it "returns false when job has no retry_on_attempts" do
      job_class = double("JobClass", retry_on_attempts: nil)
      job = double("Job", class: job_class)

      expect(handler.send(:retryable?, job)).to be false
    end

    it "returns false when job has retry_on_attempts of 0" do
      job_class = double("JobClass", retry_on_attempts: 0)
      job = double("Job", class: job_class)

      expect(handler.send(:retryable?, job)).to be false
    end
  end

  describe "#job_context" do
    let(:job) do
      double("Job",
        class: double("JobClass", name: "TestJob"),
        job_id: "123",
        queue_name: "default",
        executions: 1,
        enqueued_at: Time.now,
        scheduled_at: nil,
        arguments: ["arg1", "arg2"]
      )
    end

    it "returns basic job context" do
      context = handler.send(:job_context, job)

      expect(context).to include(
        job_class: "TestJob",
        job_id: "123",
        queue_name: "default",
        executions: 1
      )
    end

    context "when include_job_arguments is enabled" do
      before do
        Sentry.configuration.good_job.include_job_arguments = true
      end

      it "includes arguments in context" do
        context = handler.send(:job_context, job)

        expect(context[:arguments]).to eq(['"arg1"', '"arg2"'])
      end
    end

    context "when include_job_arguments is disabled" do
      before do
        Sentry.configuration.good_job.include_job_arguments = false
      end

      it "does not include arguments in context" do
        context = handler.send(:job_context, job)

        expect(context).not_to have_key(:arguments)
      end
    end
  end
end
