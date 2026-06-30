# frozen_string_literal: true

RSpec.shared_examples "an ActiveJob backend that survives Sentry instrumentation failures" do
  let(:configure_sentry) { proc { |config| config.traces_sample_rate = 1.0 } }

  it "degrades to a plain enqueue and logs when _sentry injection raises during serialize" do
    allow(Sentry).to receive(:get_trace_propagation_headers).and_raise(StandardError, "boom from injection")
    allow(Sentry.sdk_logger).to receive(:error)

    expect { successful_job.perform_later }.not_to raise_error

    expect(last_enqueued_payload).not_to be_nil
    expect(last_enqueued_payload["_sentry"]).to be_nil
    expect(Sentry.sdk_logger).to have_received(:error).with(/failed to inject _sentry payload/).at_least(:once)
  end

  it "still runs the job and logs when _sentry extraction raises during deserialize" do
    allow_any_instance_of(successful_job).to receive(:_sentry=).and_raise(StandardError, "boom from extraction")
    allow(Sentry.sdk_logger).to receive(:error)

    successful_job.perform_later
    expect { drain }.not_to raise_error

    expect(consumer_transaction).not_to be_nil
    expect(Sentry.sdk_logger).to have_received(:error).with(/failed to extract _sentry payload/).at_least(:once)
  end
end
