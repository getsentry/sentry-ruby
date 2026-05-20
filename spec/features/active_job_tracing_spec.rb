# frozen_string_literal: true

# End-to-end verification of the ActiveJob distributed-tracing extension
# this branch adds. Drives the Svelte mini app to click the "Trigger
# Job" button, which fetches POST /jobs/sample on the Rails mini app.
# The browser SDK's browserTracing integration propagates sentry-trace +
# baggage to the Rails request; the Rails AJ extension emits a
# queue.publish span on the http.server transaction at enqueue, and a
# queue.active_job consumer transaction when the :async pool runs the
# job. All three rails-side artifacts must share one trace.
RSpec.describe "ActiveJob distributed tracing", type: :e2e do
  it "links the browser fetch, the controller, the producer span, and the consumer transaction into one trace" do
    visit "/"

    expect(page).to have_content("Svelte Mini App")
    expect(page).to have_button("trigger-job-btn")

    click_button "trigger-job-btn"

    expect(page).to have_content(/Job:.*"job_id"/)

    http_txn, job_txn = wait_for_trace

    # The http.server transaction must have been entered with a
    # sentry-trace header — proof the browser SDK propagated tracing
    # state to the Rails request.
    headers = http_txn.dig("request", "headers") || {}
    sentry_trace = headers["Sentry-Trace"] || headers["sentry-trace"]
    expect(sentry_trace).to match(/^[a-f0-9]{32}-[a-f0-9]{16}(-[01])?$/)
    incoming_trace_id = sentry_trace.split("-").first

    # The controller transaction continued that trace.
    expect(http_txn.dig("contexts", "trace", "trace_id")).to eq(incoming_trace_id)
    expect(http_txn.dig("contexts", "trace", "op")).to eq("http.server")

    # queue.publish span attached to the http.server transaction.
    publish_span = http_txn["spans"].find { |s| s["op"] == "queue.publish" }
    expect(publish_span).not_to be_nil
    expect(publish_span["description"]).to eq("SampleJob")
    expect(publish_span.dig("data", "messaging.message.id")).to be_a(String)
    expect(publish_span.dig("data", "messaging.destination.name")).to eq("default")

    # Consumer transaction continued the same trace and is parented on
    # the publish span.
    expect(job_txn.dig("contexts", "trace", "trace_id")).to eq(incoming_trace_id)
    expect(job_txn.dig("contexts", "trace", "op")).to eq("queue.active_job")
    expect(job_txn.dig("contexts", "trace", "parent_span_id")).to eq(publish_span["span_id"])
    expect(job_txn.dig("contexts", "trace", "data", "messaging.message.id"))
      .to eq(publish_span.dig("data", "messaging.message.id"))
    expect(job_txn.dig("contexts", "active_job", "job_class")).to eq("SampleJob")
  end

  # The :async adapter runs the job on a separate thread, so the HTTP
  # response returns before the consumer transaction is recorded. Poll
  # the shared envelope log until both rails-side transactions are
  # present, then return them. Pair them by trace_id so an async job
  # from a prior example that landed after the per-example clear cannot
  # masquerade as this run's consumer transaction.
  def wait_for_trace(timeout: 10)
    deadline = Time.now + timeout
    loop do
      transactions = logged_envelopes.flat_map do |envelope|
        envelope["items"]
          .select { |item| item.dig("headers", "type") == "transaction" }
          .map { |item| item["payload"] }
      end

      transactions.each do |http_txn|
        next unless http_txn.dig("contexts", "trace", "op") == "http.server"
        next unless http_txn["transaction"] =~ /JobsController#sample_job/

        trace_id = http_txn.dig("contexts", "trace", "trace_id")
        job_txn = transactions.find do |t|
          t.dig("contexts", "trace", "op") == "queue.active_job" &&
            t.dig("contexts", "trace", "trace_id") == trace_id
        end
        return [http_txn, job_txn] if job_txn
      end

      break if Time.now > deadline

      sleep 0.1
    end

    raise "timed out waiting for trace"
  end
end
