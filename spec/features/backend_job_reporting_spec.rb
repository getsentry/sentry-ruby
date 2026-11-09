# frozen_string_literal: true

RSpec.describe "ActiveJob jobs on a queue backend with a Sentry integration", type: :e2e, if: Test::Helper.backend_gem_loaded? do
  it "reports the job's execution with the backend integration's origin" do
    response = post_request("/jobs/sample")
    expect(response.code).to eq("200")

    execution = wait_for("the SampleJob execution") { job_transactions("SampleJob").first }

    expect(execution.dig("contexts", "trace")).to include(
      "op" => expected_job_op,
      "origin" => expected_job_origin,
      "status" => "ok"
    )
  end

  it "continues the enqueuing request's trace in the job's transaction", if: Test::Helper.jobs_continue_enqueuing_trace? do
    response = post_request("/jobs/sample")
    expect(response.code).to eq("200")

    request, execution = wait_for("the SampleJob execution on the request's trace") do
      request = logged_payloads("transaction").find do |transaction|
        transaction.dig("contexts", "trace", "op") == "http.server" &&
          transaction.dig("request", "url").to_s.end_with?("/jobs/sample")
      end
      trace_id = request&.dig("contexts", "trace", "trace_id")
      execution = job_transactions("SampleJob").find { |transaction| transaction.dig("contexts", "trace", "trace_id") == trace_id }
      [request, execution] if execution
    end

    expect(execution.dig("contexts", "trace", "op")).to eq("queue.process")
    expect(request["spans"].map { |span| span["op"] }).to include("queue.publish")
  end
end
