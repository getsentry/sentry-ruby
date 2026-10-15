# frozen_string_literal: true

RSpec.shared_examples "an ActiveJob backend that propagates trace context through the job payload" do
  let(:configure_sentry) { proc { |config| config.traces_sample_rate = 1.0 } }

  it "produces a consumer transaction whose trace_id matches the parent transaction" do
    parent_trace_id = nil
    publish_span_id = nil

    within_parent_transaction do |parent|
      parent_trace_id = parent.trace_id
      successful_job.perform_later
      publish_span_id = parent.span_recorder.spans.find { |s| s.op == "queue.publish" }&.span_id
    end

    drain

    expect(consumer_transaction).not_to be_nil
    expect(consumer_transaction.contexts.dig(:trace, :trace_id)).to eq(parent_trace_id)
    expect(consumer_transaction.contexts.dig(:trace, :parent_span_id)).to eq(publish_span_id)
  end

  [nil, 0.0, 1.0].each do |sample_rate|
    context "with incoming baggage at sample rate #{sample_rate.inspect}" do
      let(:configure_sentry) { proc { |config| config.traces_sample_rate = sample_rate } }

      it "preserves the incoming trace and baggage through enqueue and execution" do
        reporting_job = job_fixture do
          def perform
            Sentry.capture_message("propagated", extra: { headers: Sentry.get_trace_propagation_headers })
          end
        end
        trace_id = "a" * 32
        baggage = "sentry-trace_id=#{trace_id},sentry-release=upstream,sentry-public_key=12345"
        Sentry.continue_trace({ "HTTP_SENTRY_TRACE" => "#{trace_id}-#{'b' * 16}-1", "HTTP_BAGGAGE" => baggage })

        reporting_job.perform_later
        Sentry.get_current_scope.clear
        drain

        event = sentry_events.find { |entry| entry.is_a?(Sentry::ErrorEvent) && entry.message == "propagated" }
        expect(event.contexts.dig(:trace, :trace_id)).to eq(trace_id)
        expect(event.extra[:headers]["sentry-trace"]).to start_with(trace_id)
        expect(event.extra[:headers]["baggage"]).to include("sentry-release=upstream", "sentry-trace_id=#{trace_id}")
      end
    end
  end

  it "captures a consumer transaction without raising when no parent transaction was active at enqueue" do
    expect { successful_job.perform_later }.not_to raise_error
    expect { drain }.not_to raise_error

    expect(consumer_transaction).not_to be_nil
    expect(consumer_transaction.contexts.dig(:trace, :trace_id)).to be_a(String)
  end

  it "survives a JSON round-trip of the serialized payload" do
    parent_trace_id = nil

    within_parent_transaction do |parent|
      parent_trace_id = parent.trace_id
      payload = successful_job.new.serialize
      round_tripped = JSON.parse(JSON.generate(payload))
      ::ActiveJob::Base.execute(round_tripped)
    end

    expect(consumer_transaction).not_to be_nil
    expect(consumer_transaction.contexts.dig(:trace, :trace_id)).to eq(parent_trace_id)
  end

  context "when active_job_propagate_traces is false" do
    let(:configure_sentry) do
      proc do |config|
        config.traces_sample_rate = 1.0
        config.rails.active_job_propagate_traces = false
      end
    end

    it "does not inject trace headers into the job payload" do
      within_parent_transaction do
        successful_job.perform_later
      end

      sentry_payload = last_enqueued_payload["_sentry"]
      expect(sentry_payload&.dig("trace_propagation_headers")).to be_nil
    end

    it "starts a new unconnected consumer transaction" do
      parent_trace_id = nil

      within_parent_transaction do |parent|
        parent_trace_id = parent.trace_id
        successful_job.perform_later
      end

      drain

      expect(consumer_transaction).not_to be_nil
      expect(consumer_transaction.contexts.dig(:trace, :trace_id)).not_to eq(parent_trace_id)
    end

    it "still emits a queue.publish producer span on the enqueuing transaction" do
      within_parent_transaction do
        successful_job.perform_later
      end

      parent = transactions.find { |t| t.contexts.dig(:trace, :op) == "test" }
      expect(parent).not_to be_nil

      publish_span = parent.spans.find { |s| s[:op] == "queue.publish" }
      expect(publish_span).not_to be_nil
      expect(publish_span[:description]).to eq(successful_job.name)
      expect(publish_span[:origin]).to eq("auto.queue.active_job")
    end
  end

  context "when tracing is disabled and the job carries no trace headers" do
    let(:configure_sentry) { proc { |config| config.rails.active_job_propagate_traces = false } }

    it "keeps the worker's trace on the captured error event" do
      worker_trace_id = Sentry.get_main_hub.current_scope.propagation_context.trace_id

      expect do
        failing_job.perform_later
        drain
      end.to raise_error(RuntimeError, /boom from failing_job spec/)

      error_event = sentry_events.find { |e| e.is_a?(Sentry::ErrorEvent) }
      expect(error_event.contexts.dig(:trace, :trace_id)).to eq(worker_trace_id)
    end
  end
end
