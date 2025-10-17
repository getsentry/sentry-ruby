# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sentry::GoodJob::ContextHelpers do
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

  let(:incomplete_job) do
    double("IncompleteJob",
      class: double("JobClass", name: "TestJob"),
      job_id: "123"
    )
  end

  describe ".add_context" do
    let(:base_context) { { existing: "context" } }

    it "adds GoodJob-specific context" do
      result = described_class.add_context(job, base_context)

      expect(result[:good_job]).to include(
        queue_name: "default",
        executions: 2,
        enqueued_at: job.enqueued_at,
        priority: 5
      )
    end

    it "preserves base context" do
      result = described_class.add_context(job, base_context)

      expect(result[:existing]).to eq("context")
    end

    it "when job doesn't respond to required methods" do
      result = described_class.add_context(incomplete_job, base_context)

      expect(result).to eq(base_context)
    end
  end

  describe ".add_tags" do
    let(:base_tags) { { existing: "tag" } }

    it "adds GoodJob-specific tags" do
      result = described_class.add_tags(job, base_tags)

      expect(result).to include(
        queue_name: "default",
        executions: 2,
        priority: 5
      )
    end

    it "preserves base tags" do
      result = described_class.add_tags(job, base_tags)

      expect(result[:existing]).to eq("tag")
    end

    it "when job doesn't respond to required methods" do
      result = described_class.add_tags(incomplete_job, base_tags)

      expect(result).to eq(base_tags)
    end
  end

  describe ".enhanced_context" do
    it "returns enhanced context with both ActiveJob and GoodJob data" do
      result = described_class.enhanced_context(job)

      expect(result[:active_job]).to include(
        active_job: "TestJob",
        job_id: "123",
        provider_job_id: "provider_123",
        locale: "en"
      )

      expect(result[:good_job]).to include(
        queue_name: "default",
        executions: 2,
        enqueued_at: job.enqueued_at,
        priority: 5
      )
    end
  end

  describe ".enhanced_tags" do
    it "returns enhanced tags with both ActiveJob and GoodJob data" do
      result = described_class.enhanced_tags(job)

      expect(result).to include(
        job_id: "123",
        provider_job_id: "provider_123",
        queue_name: "default",
        executions: 2,
        priority: 5
      )
    end
  end
end
