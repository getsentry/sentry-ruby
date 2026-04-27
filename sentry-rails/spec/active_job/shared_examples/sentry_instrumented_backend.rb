# frozen_string_literal: true

RSpec.shared_examples "a Sentry-instrumented ActiveJob backend" do
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

    event = last_sentry_event
    expect(event).not_to be_nil

    exception = extract_sentry_exceptions(event).first
    expect(exception.value).to match(/boom from failing_job spec/)
  end
end
