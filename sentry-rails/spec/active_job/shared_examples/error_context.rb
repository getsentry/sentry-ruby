# frozen_string_literal: true

RSpec.shared_examples "an ActiveJob backend that attaches job context to error events" do
  let(:failing_job) do
    job_fixture do
      def perform
        a = 1
        b = 0
        raise "boom from failing_job spec"
      end
    end
  end

  it "attaches job context to extras and tags on the captured event" do
    expect do
      failing_job.perform_later
      drain
    end.to raise_error(RuntimeError, /boom from failing_job spec/)

    event = last_sentry_event

    expect(event.extra).to include(
      active_job: failing_job.name,
      arguments: [],
      job_id: a_kind_of(String)
    )
    expect(event.extra).to have_key(:provider_job_id)
    expect(event.extra).to have_key(:locale)
    expect(event.extra).to have_key(:scheduled_at)

    expect(event.tags).to include(
      job_id: event.extra[:job_id],
      provider_job_id: event.extra[:provider_job_id]
    )

    last_frame = event.exception.values.first.stacktrace.frames.last
    expect(last_frame.vars).to include(a: "1", b: "0")
  end
end
