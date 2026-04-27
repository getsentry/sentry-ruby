# frozen_string_literal: true

RSpec.shared_examples "an ActiveJob backend that captures errors" do
  let(:failing_job) do
    job_fixture do
      def perform
        raise "boom from failing_job spec"
      end
    end
  end

  it "captures an error event when a job fails" do
    expect do
      failing_job.perform_later
      drain
    end.to raise_error(RuntimeError, /boom from failing_job spec/)

    expect(sentry_events.size).to eq(1)

    exception = extract_sentry_exceptions(sentry_events.last).first
    expect(exception.value).to match(/boom from failing_job spec/)
  end
end
