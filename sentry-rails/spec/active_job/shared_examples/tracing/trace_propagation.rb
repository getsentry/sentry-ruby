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
end
