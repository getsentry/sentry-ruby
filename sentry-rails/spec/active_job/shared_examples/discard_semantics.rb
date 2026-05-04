# frozen_string_literal: true

RSpec.shared_examples "an ActiveJob backend that respects discard semantics" do
  let(:discardable_job) do
    job_fixture do
      discard_on StandardError

      def perform
        raise "boom from discardable_job spec"
      end
    end
  end

  it "does not capture an event when the job is discarded" do
    expect do
      discardable_job.perform_later
      drain
    end.not_to raise_error

    expect(sentry_events).to be_empty
  end
end
