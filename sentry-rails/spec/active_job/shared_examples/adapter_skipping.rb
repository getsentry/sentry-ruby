# frozen_string_literal: true

RSpec.shared_examples "an ActiveJob backend that respects skippable_job_adapters" do
  let(:failing_job) do
    job_fixture do
      def perform
        raise "boom from failing_job spec"
      end
    end
  end

  it "captures no events when the adapter is in skippable_job_adapters" do
    Sentry.configuration.rails.skippable_job_adapters = [
      failing_job.queue_adapter.class.to_s
    ]

    expect do
      failing_job.perform_later
      drain
    end.to raise_error(RuntimeError, /boom from failing_job spec/)

    expect(sentry_events).to be_empty
  end
end
