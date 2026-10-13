# frozen_string_literal: true

require "spec_helper"
require "timecop"
require "sidekiq/api"

RSpec.describe Sentry::Sidekiq::JobExtension do
  let(:queue) { Sidekiq::Queue.new("default") }
  let(:trace_headers) { { "sentry-trace" => "#{"a" * 32}-#{"b" * 16}-1", "baggage" => "sentry-trace_id=#{"a" * 32}" } }

  def delivered_job(**options)
    Sidekiq::Client.push({ "queue" => "default", "class" => HappyWorker, "args" => [] }.merge(options.transform_keys(&:to_s)))
    queue.first.item.merge("queue" => "default")
  end

  def call_hook(hook, job, *arguments)
    keywords = { job: job }
    keywords[:payload] = job if %i[inject_trace_headers extract_trace_headers].include?(hook)
    keywords[:headers] = arguments.first if hook == :inject_trace_headers
    Sentry.job_extensions.call(Sentry.job_extensions.for(job), hook, **keywords)
  end

  before do
    perform_basic_setup
    queue.clear
  end

  after do
    queue.clear
  end

  it "describes the delivered job's message id, queue and receive latency in milliseconds" do
    job = delivered_job

    data = Timecop.freeze(Time.now + 10) do
      Timecop.mock_process_clock = true
      call_hook(:messaging_data, job)
    ensure
      Timecop.mock_process_clock = false
    end

    expect(data).to include(message_id: job["jid"], destination: "default")
    expect(data[:receive_latency]).to be_within(1_000).of(10_000)
  end

  it "omits the receive latency of a job without an enqueue time" do
    job = delivered_job.reject { |key, _value| key == "enqueued_at" }

    expect(call_hook(:messaging_data, job)).to eq(message_id: job["jid"], destination: "default")
  end

  it "reports a first attempt as zero retries that Sidekiq will retry" do
    expect(call_hook(:retry_info, delivered_job(retry: 1))).to eq(count: 0, will_retry: true)
  end

  it "reports the retries a retried job has gone through" do
    expect(call_hook(:retry_info, delivered_job(retry: 5, retry_count: 2))).to eq(count: 2, will_retry: true)
  end

  it "reports that Sidekiq will not retry a job with retries disabled or exhausted" do
    expect(call_hook(:retry_info, delivered_job(retry: false))).to eq(count: 0, will_retry: false)
    expect(call_hook(:retry_info, delivered_job(retry: 3, retry_count: 3))).to eq(count: 3, will_retry: false)
  end

  it "reports that Sidekiq will not retry the final delivered attempt" do
    expect(call_hook(:retry_info, delivered_job(retry: 1, retry_count: 0))).to eq(count: 0, will_retry: false)
  end

  it "describes the job as the sidekiq context with queue, jid and sidekiq tags" do
    job = delivered_job(tags: ["marvel", "dc"])

    expect(call_hook(:scope_data, job)).to eq(
      contexts: { sidekiq: job },
      tags: { queue: "default", jid: job["jid"], "sidekiq.marvel": true, "sidekiq.dc": true }
    )
  end

  it "carries trace propagation headers in a copy of the job" do
    job = { "class" => "HappyWorker", "jid" => "123" }

    expect(call_hook(:inject_trace_headers, job, trace_headers)).to eq(job.merge("trace_propagation_headers" => trace_headers))
    expect(job).not_to have_key("trace_propagation_headers")
  end

  it "keeps the trace propagation headers a job already carries" do
    job = { "class" => "HappyWorker", "jid" => "123", "trace_propagation_headers" => trace_headers }

    expect(call_hook(:inject_trace_headers, job, { "sentry-trace" => "other" })).to eq(job)
  end

  it "reads the trace propagation headers the job carries" do
    expect(call_hook(:extract_trace_headers, delivered_job(trace_propagation_headers: trace_headers))).to eq(trace_headers)
  end
end
