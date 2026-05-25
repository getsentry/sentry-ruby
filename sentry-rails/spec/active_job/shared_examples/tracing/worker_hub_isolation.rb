# frozen_string_literal: true

# These specs guard the hub-isolation contract around ActiveJob execution:
# inside +SentryReporter.record+ the SDK clones the main hub onto the
# current thread, runs the job under +with_scope+, and restores whatever
# hub was on the thread before. The restore matters in two real-world
# flows that are simulated below:
#
#   * Inline jobs dispatched from a Rack request — the request thread
#     already owns a hub (set up by +Sentry::Rack::CaptureExceptions+),
#     and the rest of the request must keep seeing that hub after the
#     job returns.
#   * Recycled worker-pool threads — a previous job's scope must not
#     leak into the next job on the same thread.
#
# We assert these properties through observable SDK output (event tags
# on the captured events / consumer transactions)
RSpec.shared_examples "an ActiveJob backend that isolates Sentry context per worker thread" do
  let(:configure_sentry) { proc { |config| config.traces_sample_rate = 1.0 } }

  let(:tagging_job) do
    job_fixture do
      def perform
        Sentry.get_current_scope.set_tags(layer: "job")
        Sentry.capture_message("from-job")
      end
    end
  end

  # Stand in for +Sentry::Rack::CaptureExceptions+: give the test thread
  # its own hub cloned from main and mutate its scope, the way a live
  # request would before dispatching an inline job.
  before do
    Sentry.clone_hub_to_current_thread
    Sentry.get_current_scope.set_tags(layer: "request")
  end

  it "runs the job under a fresh scope cloned from the main hub, not the caller's scope" do
    tagging_job.perform_later
    drain

    job_event = sentry_events.find { |e| e.is_a?(Sentry::ErrorEvent) && e.message == "from-job" }
    expect(job_event).not_to be_nil
    expect(job_event.tags[:layer]).to eq("job")

    expect(consumer_transaction).not_to be_nil
    expect(consumer_transaction.tags[:layer]).to eq("job")
  end

  it "restores the caller's hub so events captured after the job carry the caller's scope" do
    tagging_job.perform_later
    drain

    Sentry.capture_message("from-caller")

    caller_event = sentry_events.find { |e| e.is_a?(Sentry::ErrorEvent) && e.message == "from-caller" }
    expect(caller_event).not_to be_nil
    expect(caller_event.tags[:layer]).to eq("request")
  end

  it "does not leak scope mutations between jobs that share a worker thread" do
    job_a = job_fixture do
      def perform
        Sentry.get_current_scope.set_tags(run: "A")
        Sentry.capture_message("job-a")
      end
    end

    job_b = job_fixture do
      def perform
        Sentry.get_current_scope.set_tags(run: "B")
        Sentry.capture_message("job-b")
      end
    end

    job_a.perform_later
    drain
    job_b.perform_later
    drain

    event_a = sentry_events.find { |e| e.is_a?(Sentry::ErrorEvent) && e.message == "job-a" }
    event_b = sentry_events.find { |e| e.is_a?(Sentry::ErrorEvent) && e.message == "job-b" }

    expect(event_a.tags[:run]).to eq("A")
    expect(event_b.tags[:run]).to eq("B")
  end
end
