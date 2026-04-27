# frozen_string_literal: true

RSpec.shared_examples "a Sentry-instrumented ActiveJob backend" do
  it "captures an error event when a job fails" do
    expect do
      Sentry::Specs::ActiveJob::FailingJob.perform_later
      drain
    end.to raise_error(Sentry::Specs::ActiveJob::FailingJob::Boom)

    event = last_sentry_event
    expect(event).not_to be_nil

    exception = extract_sentry_exceptions(event).first
    expect(exception.type).to eq("Sentry::Specs::ActiveJob::FailingJob::Boom")
  end
end
