# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sentry::GoodJob::ActiveJobExtensions do
  let(:job) do
    double("Job",
      class: double("JobClass", name: "TestJob"),
      job_id: "123",
      provider_job_id: "provider_123",
      queue_name: "default",
      executions: 2,
      enqueued_at: Time.now,
      scheduled_at: Time.now + 1.hour,
      priority: 5,
      arguments: ["arg1", "arg2"],
      locale: "en"
    )
  end

  let(:base_context) { { active_job: "TestJob" } }
  let(:base_tags) { { job_id: "123" } }

  before do
    perform_basic_setup
  end

  describe ".enhance_sentry_context" do
    it "enhances sentry context with GoodJob-specific data" do
      result = described_class.enhance_sentry_context(job, base_context)

      expect(result[:good_job]).to include(
        queue_name: "default",
        executions: 2,
        enqueued_at: job.enqueued_at,
        priority: 5
      )
    end

    it "preserves base context" do
      result = described_class.enhance_sentry_context(job, base_context)

      expect(result[:active_job]).to eq("TestJob")
    end

    it "returns base context when job doesn't respond to required methods" do
      incomplete_job = double("IncompleteJob", job_id: "123")
      result = described_class.enhance_sentry_context(incomplete_job, base_context)

      expect(result).to eq(base_context)
    end
  end

  describe ".enhance_sentry_tags" do
    it "enhances sentry tags with GoodJob-specific data" do
      result = described_class.enhance_sentry_tags(job, base_tags)

      expect(result).to include(
        job_id: "123",
        queue_name: "default",
        executions: 2,
        priority: 5
      )
    end

    it "preserves base tags" do
      result = described_class.enhance_sentry_tags(job, base_tags)

      expect(result[:job_id]).to eq("123")
    end

    it "returns base tags when job doesn't respond to required methods" do
      incomplete_job = double("IncompleteJob", job_id: "123")
      result = described_class.enhance_sentry_tags(incomplete_job, base_tags)

      expect(result).to eq(base_tags)
    end
  end

  describe ".setup" do
    it "sets up GoodJob-specific ActiveJob extensions" do
      # Mock Rails and Sentry to ensure conditions are met
      stub_const("Rails", double("Rails"))
      allow(Sentry).to receive(:initialized?).and_return(true)

      # Mock SentryReporter to be defined
      stub_const("Sentry::Rails::ActiveJobExtensions::SentryReporter", Class.new)

      # Mock ActiveSupport.on_load to test it's called
      allow(ActiveSupport).to receive(:on_load).with(:active_job).and_yield

      # Mock the private methods to test they are called
      allow(described_class).to receive(:enhance_sentry_reporter)
      allow(described_class).to receive(:setup_good_job_extensions)

      described_class.setup

      expect(described_class).to have_received(:enhance_sentry_reporter)
      expect(described_class).to have_received(:setup_good_job_extensions)
    end
  end

  describe "GoodJobExtensions" do
    let(:job_class) do
      Class.new(ActiveJob::Base) do
        include Sentry::GoodJob::ActiveJobExtensions::GoodJobExtensions

        def self.name
          "TestJob"
        end

        def perform
          "test"
        end
      end
    end

    let(:job) { job_class.new }

    before do
      perform_basic_setup
    end

    describe "around_enqueue" do
      it "creates child span for enqueue with GoodJob-specific data" do
        expect(Sentry).to receive(:with_child_span).with(op: "queue.publish", description: "TestJob")
        job.enqueue
      end
    end

    describe "around_perform" do
      it "adds GoodJob-specific tags during perform" do
        scope = double("Scope")
        allow(scope).to receive(:set_tags)
        allow(scope).to receive(:span).and_return(nil)

        expect(Sentry).to receive(:with_scope).and_yield(scope)
        job.perform_now
      end
    end
  end
end
