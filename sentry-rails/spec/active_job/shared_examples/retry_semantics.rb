# frozen_string_literal: true

RSpec.shared_examples "an ActiveJob backend that respects retry semantics" do
  let(:retryable_job) do
    job_fixture do
      retry_on StandardError, attempts: 3, wait: 0

      def perform
        raise "boom from retryable_job spec"
      end
    end
  end

  it "captures one error event after retries are exhausted" do
    expect do
      retryable_job.perform_later
      3.times { drain }
    end.to raise_error(RuntimeError, /boom from retryable_job spec/)

    expect(sentry_events.size).to eq(1)

    exception = extract_sentry_exceptions(sentry_events.last).first
    expect(exception.value).to match(/boom from retryable_job spec/)
  end
end
