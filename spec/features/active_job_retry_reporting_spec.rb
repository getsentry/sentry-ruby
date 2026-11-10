# frozen_string_literal: true

RSpec.describe "ActiveJob retry reporting", type: :e2e, if: Test::Helper.backend_retries_jobs? do
  it "reports each of a failing job's three attempts once, inside that attempt's transaction" do
    response = post_request("/jobs/retried")
    expect(response.code).to eq("200")

    executions, errors = wait_for("three attempts of the retried job", timeout: 60, settle: 2) do
      executions = job_transactions("RetriedJob")
      errors = logged_payloads("event").select do |event|
        Array(event.dig("exception", "values")).last.to_h["value"].to_s.start_with?("Intentional retried job failure")
      end
      [executions, errors] if executions.size >= 3 && errors.size >= 3
    end

    expect(executions.size).to eq(3)
    expect(errors.size).to eq(3)

    executions.each do |execution|
      expect(execution.dig("contexts", "trace")).to include("op" => expected_job_op, "status" => "internal_error")
    end

    expect(errors.map { |error| error.dig("contexts", "trace", "span_id") })
      .to match_array(executions.map { |execution| execution.dig("contexts", "trace", "span_id") })

    expect(executions.map { |execution| execution.dig("contexts", "trace", "data", "messaging.message.id") }.uniq.size).to eq(1)
  end

  it "keeps every attempt of a retried job in the enqueuing request's trace",
     if: Test::Helper.backend_retries_jobs? && Test::Helper.job_executions_share_a_trace? do
    response = post_request("/jobs/retried")
    expect(response.code).to eq("200")

    request, executions = wait_for("three attempts of the retried job", timeout: 60, settle: 2) do
      request = logged_payloads("transaction").find do |transaction|
        transaction.dig("contexts", "trace", "op") == "http.server" &&
          transaction.dig("request", "url").to_s.end_with?("/jobs/retried")
      end
      executions = job_transactions("RetriedJob")
      [request, executions] if request && executions.size >= 3
    end

    expect(executions.map { |execution| execution.dig("contexts", "trace", "trace_id") }.uniq)
      .to eq([request.dig("contexts", "trace", "trace_id")])
    expect(executions.map { |execution| execution.dig("contexts", "trace", "parent_span_id") }.uniq.size).to eq(1)
  end
end
