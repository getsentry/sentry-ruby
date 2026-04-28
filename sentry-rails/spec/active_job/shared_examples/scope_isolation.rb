# frozen_string_literal: true

RSpec.shared_examples "an ActiveJob backend that isolates per-job scope" do
  let(:scope_polluting_job) do
    job_fixture do
      def perform
        Sentry.get_current_scope.set_extras(scope_marker: "from-job")
        raise "boom from scope_polluting_job spec"
      end
    end
  end

  it "applies in-job scope changes to the captured event but does not leak them" do
    expect do
      scope_polluting_job.perform_later
      drain
    end.to raise_error(RuntimeError, /boom from scope_polluting_job spec/)

    event = last_sentry_event
    expect(event.extra).to include(scope_marker: "from-job")

    expect(Sentry.get_current_scope.extra).to eq({})
  end
end
