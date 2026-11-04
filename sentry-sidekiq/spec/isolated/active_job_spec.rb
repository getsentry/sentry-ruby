# frozen_string_literal: true

require_relative "support/rails_app"
require "active_job/railtie"
require "sidekiq/api"

RSpec.describe "ActiveJob jobs on Sidekiq when the Sidekiq adapter is not skippable" do
  let(:processor) { new_processor }
  let(:transport) { Sentry.get_current_client.transport }

  let(:succeeding_job) do
    stub_const("SucceedingJob", Class.new(ActiveJob::Base) do
      self.queue_adapter = :sidekiq
      queue_as :events

      def perform(*); end
    end)
  end

  let(:failing_job) do
    stub_const("FailingJob", Class.new(ActiveJob::Base) do
      self.queue_adapter = :sidekiq
      queue_as :events

      def perform(*)
        raise "job failed"
      end
    end)
  end

  before do
    make_basic_app do |config|
      config.traces_sample_rate = 1.0
      config.rails.skippable_job_adapters.delete("ActiveJob::QueueAdapters::SidekiqAdapter")
    end
  end

  after do
    Sidekiq::Queue.new("events").clear
    Sidekiq::RetrySet.new.clear
  end

  def enqueued_message(job_class, *arguments)
    queue = Sidekiq::Queue.new("events")
    queue.clear
    job_class.perform_later(*arguments)
    message = queue.first.item
    queue.clear
    message
  end

  # With retries enabled, Sidekiq's retry handler looks up the missing
  # "wrapped" class itself and reports a second NameError, as it does on
  # master, so examples counting events disable retries.
  def removed_job_message(retries: false)
    message = enqueued_message(succeeding_job)
    message["wrapped"] = "RemovedJob"
    message["args"].first["job_class"] = "RemovedJob"
    message["retry"] = false unless retries
    message
  end

  def deliver(message)
    transport.events.clear
    process_work(processor, Sidekiq::BasicFetch::UnitOfWork.new("queue:#{message["queue"]}", Sidekiq.dump_json(message)))
    transport.events.dup
  end

  def consumer_transactions(events)
    events.select { |event| event.is_a?(Sentry::TransactionEvent) && event.contexts.dig(:trace, :op) == "queue.process" }
  end

  it "reports the job once through sentry-rails under Sidekiq's transaction name and origin" do
    transactions = consumer_transactions(deliver(enqueued_message(succeeding_job)))

    expect(transactions.size).to eq(1)
    expect(transactions.first.transaction).to eq("Sidekiq/SucceedingJob")
    expect(transactions.first.contexts.dig(:trace, :origin)).to eq("auto.queue.sidekiq")
    expect(transactions.first.contexts[:active_job]).to include(job_class: "SucceedingJob", queue: "events")
  end

  it "captures a failing job once with its ActiveJob context" do
    message = enqueued_message(failing_job)

    events = deliver(message)

    errors = events.grep(Sentry::ErrorEvent)
    expect(errors.size).to eq(1)
    expect(errors.first.transaction).to eq("Sidekiq/FailingJob")
    expect(errors.first.contexts[:active_job]).to include(job_class: "FailingJob", provider_job_id: message["jid"])
    expect(errors.first.contexts.dig(:trace, :span_id)).to eq(consumer_transactions(events).first.contexts.dig(:trace, :span_id))
  end

  it "captures an error raised before the job runs once through sentry-sidekiq" do
    message = removed_job_message

    errors = deliver(message).grep(Sentry::ErrorEvent)

    expect(errors.size).to eq(1)
    expect(errors.first.exception.values.first.mechanism.type).to eq("sidekiq")
    expect(errors.first.contexts[:sidekiq]).to include("jid" => message["jid"], "queue" => "events")
  end

  it "applies Sidekiq's retry reporting to an error raised before the job runs" do
    Sentry.configuration.sidekiq.report_after_job_retries = true
    message = removed_job_message(retries: true)
    expect(message["retry"]).to be(true)

    errors = deliver(message).grep(Sentry::ErrorEvent)

    expect(errors).to be_empty
  end

  it "keeps the app's global scope data on an error raised before the job runs after a plain Sidekiq job" do
    Sentry.get_main_hub.current_scope.set_tags(app_tag: "global")
    execute_worker(processor, HappyWorker)

    errors = deliver(removed_job_message).grep(Sentry::ErrorEvent)

    expect(errors.size).to eq(1)
    expect(errors.first.tags).to include(app_tag: "global")
  end

  it "leaves the app's global scope data in place after an error raised before the job runs" do
    Sentry.get_main_hub.current_scope.set_tags(app_tag: "global")

    deliver(removed_job_message)

    expect(Sentry.get_main_hub.current_scope.tags).to include(app_tag: "global")
  end

  it "continues the trace of the transaction that enqueued the job on an error raised before the job runs" do
    parent = Sentry.start_transaction(name: "enqueuer", op: "test")
    Sentry.get_current_scope.set_span(parent)
    message = removed_job_message
    parent.finish
    Sentry.get_current_scope.clear
    expect(message["trace_propagation_headers"]).to include("sentry-trace")

    errors = deliver(message).grep(Sentry::ErrorEvent)

    expect(errors.first.contexts.dig(:trace, :trace_id)).to eq(parent.trace_id)
  end

  it "starts a new trace for an error raised before a job without trace headers runs" do
    Sentry.configuration.sidekiq.propagate_traces = false
    worker_trace_id = Sentry.get_main_hub.current_scope.propagation_context.trace_id
    message = removed_job_message
    expect(message).not_to have_key("trace_propagation_headers")

    errors = deliver(message).grep(Sentry::ErrorEvent)

    expect(errors.first.contexts.dig(:trace, :trace_id)).not_to eq(worker_trace_id)
  end

  it "reports an error that retry_on retries when active_job_report_on_retry_error is enabled" do
    stub_const("RetryingJob", Class.new(ActiveJob::Base) do
      self.queue_adapter = :sidekiq
      queue_as :events
      retry_on StandardError, attempts: 2, wait: 0

      def perform(*)
        raise "job failed on its first attempt"
      end
    end)
    Sentry.configuration.rails.active_job_report_on_retry_error = true

    errors = deliver(enqueued_message(RetryingJob)).grep(Sentry::ErrorEvent)

    expect(errors.map { |error| error.exception.values.first.value }).to include(/job failed on its first attempt/)
  end

  it "continues the trace of the transaction that enqueued the job" do
    parent = Sentry.start_transaction(name: "enqueuer", op: "test")
    Sentry.get_current_scope.set_span(parent)
    message = enqueued_message(succeeding_job, "sku")
    parent.finish
    Sentry.get_current_scope.clear

    transaction = consumer_transactions(deliver(message)).first

    expect(transaction.contexts[:trace]).to include(trace_id: parent.trace_id)
  end

  it "keeps reporting plain Sidekiq workers through sentry-sidekiq" do
    transport.events.clear

    execute_worker(processor, HappyWorker)

    transaction = consumer_transactions(transport.events).first
    expect(transaction.transaction).to eq("Sidekiq/HappyWorker")
    expect(transaction.contexts).not_to have_key(:active_job)
  end
end
