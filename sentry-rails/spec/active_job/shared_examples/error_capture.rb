# frozen_string_literal: true

RSpec.shared_examples "an ActiveJob backend that captures errors" do
  it "captures an error event when a job fails" do
    expect do
      failing_job.perform_later
      drain
    end.to raise_error(RuntimeError, /boom from failing_job spec/)

    expect(sentry_events.size).to eq(1)

    exception = extract_sentry_exceptions(sentry_events.last).first
    expect(exception.value).to match(/boom from failing_job spec/)
  end

  context "when the background worker exits before flushing" do
    let(:background_worker) { ManualBackgroundWorker.new }

    let(:sentry_test_config) do
      proc { |config| config.background_worker_threads = 1 }
    end

    before { Sentry.background_worker = background_worker }

    it "captures the error synchronously so it survives the worker exiting" do
      expect do
        failing_job.perform_later
        drain
      end.to raise_error(RuntimeError, /boom from failing_job spec/)

      expect(background_worker.pending).to be_empty
      expect(sentry_events.size).to eq(1)

      background_worker.drop!

      expect(sentry_events.size).to eq(1)
    end
  end
end
