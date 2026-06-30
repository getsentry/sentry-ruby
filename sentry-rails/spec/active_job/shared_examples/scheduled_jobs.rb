# frozen_string_literal: true

RSpec.shared_examples "an ActiveJob backend that records scheduled_at on delayed jobs" do
  it "records scheduled_at in the event extras", skip: RAILS_VERSION < 6.1 do
    expect do
      failing_job.set(wait: 5.seconds).perform_later
      drain(at: 1.minute.from_now)
    end.to raise_error(RuntimeError, /boom from failing_job spec/)

    expect(last_sentry_event.extra[:scheduled_at]).not_to be_nil
  end
end
