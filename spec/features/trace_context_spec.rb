# frozen_string_literal: true

RSpec.describe "Trace context", type: :e2e do
  def early_middleware_logs
    logged_log_events.select { |log| log["body"] == "early middleware log" }
  end

  def request_transaction
    logged_events[:events].find do |event|
      event["type"] == "transaction" && event.dig("contexts", "trace", "op") == "http.server"
    end
  end

  it "gives a log emitted before CaptureExceptions the transaction's trace_id" do
    without_trace_propagation { make_request("/trace_context") }

    expect(early_middleware_logs.first["trace_id"])
      .to eq(request_transaction.dig("contexts", "trace", "trace_id"))
  end

  it "continues an incoming distributed trace in a log emitted before CaptureExceptions" do
    incoming_trace_id = propagated_trace_id

    make_request("/trace_context")

    expect(early_middleware_logs.first["trace_id"]).to eq(incoming_trace_id)
  end

  it "starts a new trace for every request that arrives without one" do
    without_trace_propagation { 2.times { make_request("/trace_context") } }

    trace_ids = early_middleware_logs.map { |log| log["trace_id"] }

    expect(trace_ids.length).to eq(2)
    expect(trace_ids.uniq.length).to eq(2)
  end
end
