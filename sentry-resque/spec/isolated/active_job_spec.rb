# frozen_string_literal: true

require "rails"
require "securerandom"

return if Rails.version.to_f < 7.2

begin
  require "mock_redis"
  require "resque"
  require "resque-scheduler"
rescue LoadError
  return
end

require_relative "support/rails_app"

RSpec.describe "ActiveJob jobs on Resque with sentry-resque loaded", type: :job do
  include ActiveSupport::Testing::TimeHelpers
  include_context "active_job backend harness", adapter: :resque
  include_context "resque adapter"

  let(:job_span_origin) { "auto.queue.resque" }
  let(:skipped_adapter_error_events) { 1 }
  let(:reports_retried_exceptions) { false }

  def expected_message_body_size(delivered_job_data)
    active_job_payload = delivered_job_data.except(Sentry::Resque::ActiveJobSupport::RESQUE_JOB_KEY)
    Resque.encode("class" => ActiveJob::QueueAdapters::ResqueAdapter::JobWrapper.name, "args" => [active_job_payload]).bytesize
  end

  it_behaves_like "a Sentry-instrumented ActiveJob backend"
  it_behaves_like "an ActiveJob backend that supports distributed tracing"

  context "after Sentry.init runs again without the ActiveJob hand-off" do
    before do
      Sentry.init do |config|
        config.dsn = Sentry::TestHelper::DUMMY_DSN
        config.transport.transport_class = Sentry::DummyTransport
        config.background_worker_threads = 0
        config.sdk_logger = ::Logger.new(nil)
        config.traces_sample_rate = 1.0
      end
    end

    it "should preserve Rails identity and serialized trace propagation when the job succeeds" do
      parent = Sentry.start_transaction(name: "enqueue", op: "test")
      Sentry.get_current_scope.set_span(parent)
      job = successful_job.perform_later
      payload = last_enqueued_payload
      parent.finish
      Sentry.get_current_scope.clear

      drain

      consumer_transactions = transactions.select { |event| event.contexts.dig(:trace, :op).start_with?("queue.") }
      rails_transaction = consumer_transactions.find { |event| event.contexts.key?(:active_job) }

      aggregate_failures do
        expect(consumer_transactions.size).to eq(2)
        expect(rails_transaction.transaction).to eq(job.class.name)
        expect(rails_transaction.contexts.dig(:trace, :origin)).to eq("auto.queue.active_job")
        expect(payload.dig("_sentry", "trace_propagation_headers", "sentry-trace"))
          .to start_with("#{parent.trace_id}-")
        expect(rails_transaction.contexts.dig(:trace, :trace_id)).to eq(parent.trace_id)
      end
    end

    it "should preserve the Rails error mechanism and transaction identity when the job fails" do
      job = failing_job.perform_later

      expect { drain }.to raise_error(RuntimeError, /boom from failing_job spec/)

      rails_transaction = transactions.find { |event| event.contexts.key?(:active_job) }
      error = sentry_events.grep(Sentry::ErrorEvent).find { |event| event.contexts.key?(:active_job) }

      aggregate_failures do
        expect(rails_transaction.transaction).to eq(job.class.name)
        expect(rails_transaction.contexts.dig(:trace, :origin)).to eq("auto.queue.active_job")
        expect(error.transaction).to eq(job.class.name)
        expect(error.exception.values.first.mechanism.type).to eq("rails")
        expect(error.contexts.dig(:trace, :span_id)).to eq(rails_transaction.contexts.dig(:trace, :span_id))
      end
    end
  end

  context "with the resque adapter opted in to the ActiveJob integration" do
    let(:configure_sentry) { proc { |config| config.traces_sample_rate = 1.0 } }

    def error_events
      sentry_events.grep(Sentry::ErrorEvent)
    end

    it "reports a failing job once, within one consumer transaction that keeps the sentry-resque identity" do
      failing_job.set(queue: "events").perform_later

      expect { drain }.to raise_error(RuntimeError, /boom from failing_job spec/)

      consumer_transactions = transactions.select { |t| t.contexts.dig(:trace, :op) == "queue.process" }
      expect(consumer_transactions.size).to eq(1)
      expect(error_events.size).to eq(1)

      transaction = consumer_transactions.first
      error_event = error_events.first
      expect(transaction.contexts.dig(:trace, :origin)).to eq("auto.queue.resque")
      expect(transaction.tags).to include("resque.queue" => "events")
      expect(transaction.contexts[:"Active-Job"]).to include(job_class: failing_job.name, queue: "events")
      expect(error_event.tags).to include("resque.queue" => "events")
      expect(error_event.contexts[:"Active-Job"]).to include(job_class: failing_job.name, queue: "events")
      expect(error_event.sdk[:name]).to eq("sentry.ruby.resque")
    end

    it "should record one failed consumer transaction when a queued job class is removed" do
      parent_trace_id = nil
      job = nil
      within_parent_transaction do |parent|
        parent_trace_id = parent.trace_id
        job = successful_job.set(queue: "events").perform_later
      end
      hide_const(job.class.name)

      expect { drain }.to raise_error(NameError)

      consumer_transactions = transactions.select { |event| event.contexts.dig(:trace, :op) == "queue.process" }
      expect(error_events.size).to eq(1)
      expect(consumer_transactions.size).to eq(1)

      transaction = consumer_transactions.first
      expect(transaction.transaction).to eq(job.class.name)
      expect(transaction.contexts.dig(:trace, :status)).to eq("internal_error")
      expect(transaction.contexts.dig(:trace, :origin)).to eq("auto.queue.resque")
      expect(transaction.contexts.dig(:trace, :trace_id)).to eq(parent_trace_id)
      expect(transaction.contexts.dig(:trace, :data)).to include(
        "messaging.system" => "resque",
        "messaging.message.id" => job.job_id,
        "messaging.destination.name" => "events"
      )
      expect(error_events.first.contexts.dig(:trace, :span_id)).to eq(transaction.contexts.dig(:trace, :span_id))
    end

    it "records the resque messaging attributes on the consumer transaction" do
      job = successful_job.set(queue: "events").perform_later
      drain

      expect(consumer_transaction.contexts.dig(:trace, :data)).to include(
        "messaging.system" => "resque",
        "messaging.message.id" => job.job_id,
        "messaging.destination.name" => "events"
      )
    end

    it "records messaging.system resque on the queue.publish producer span" do
      within_parent_transaction { successful_job.perform_later }

      parent = transactions.find { |t| t.contexts.dig(:trace, :op) == "test" }
      publish_span = parent.spans.find { |span| span[:op] == "queue.publish" }
      expect(publish_span[:data]).to include("messaging.system" => "resque")
    end
  end
end
