# frozen_string_literal: true

RSpec.describe "ActiveJob error reporting", type: :e2e, unless: Test::Helper.runs_jobs_in_request? do
  it "reports each failed execution of a job exactly once, inside that execution's transaction" do
    response = post_request("/jobs/failing")
    expect(response.code).to eq("200")

    executions, errors = wait_for("the failed job execution", settle: 1) do
      executions = job_transactions("FailingJob")
      errors = logged_payloads("event")
      [executions, errors] unless executions.empty? || errors.empty?
    end

    executions.each do |execution|
      expect(execution.dig("contexts", "trace")).to include(
        "op" => expected_job_op,
        "status" => "internal_error"
      )
    end

    expect(errors.size).to eq(executions.size)
    expect(errors.map { |error| error.dig("contexts", "trace", "span_id") })
      .to match_array(executions.map { |execution| execution.dig("contexts", "trace", "span_id") })

    errors.each do |error|
      expect(error.dig("exception", "values").last).to include(
        "type" => "StandardError",
        "value" => a_string_starting_with("Intentional job failure for testing")
      )
    end
  end
end
