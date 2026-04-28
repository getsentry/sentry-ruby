# frozen_string_literal: true

RSpec.shared_examples "an ActiveJob backend that records scheduled_at on delayed jobs" do
  let(:failing_job) do
    job_fixture do
      def perform
        raise "boom from scheduled_jobs spec"
      end
    end
  end

  it "records scheduled_at in the event extras" do
    expect do
      failing_job.set(wait: 5.seconds).perform_later
      drain(at: 1.minute.from_now)
    end.to raise_error(RuntimeError, /boom from scheduled_jobs spec/)

    expect(last_sentry_event.extra[:scheduled_at]).not_to be_nil
  end
end
