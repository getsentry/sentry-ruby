# frozen_string_literal: true

RSpec.shared_examples "an ActiveJob backend that unwraps DeserializationError" do
  let(:deserialization_error_job) do
    job_fixture do
      def perform
        1 / 0
      rescue
        err = ActiveJob::DeserializationError.new
        # DeserializationError#initialize copies $!.backtrace, which on JRuby can
        # contain nil elements for frames defined in anonymous Class.new blocks.
        # Compact the backtrace to avoid a JRuby NPE in traceRaise at shutdown.
        err.set_backtrace(Array(err.backtrace).compact)
        raise err
      end
    end
  end

  it "captures the root cause when wrapped in ActiveJob::DeserializationError" do
    expect do
      deserialization_error_job.perform_later
      drain
    end.to raise_error(ActiveJob::DeserializationError)

    expect(sentry_events.size).to eq(1)

    types = extract_sentry_exceptions(sentry_events.last).map(&:type)
    expect(types.first).to eq("ZeroDivisionError")
  end
end
