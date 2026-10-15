# frozen_string_literal: true

require "sentry/integrable"

module Sentry
  module TestJobsIntegration
    extend Sentry::Integrable

    register_integration name: "test_jobs", version: "1.0"
  end
end

RSpec.describe Sentry::JobExtensions::Consumer do
  let(:job) { Struct.new(:id, :queue).new("job-1", "critical") }
  let(:integration) { Sentry::TestJobsIntegration }
  let(:string_io) { StringIO.new }

  def consumer(**hooks)
    registry = Sentry::JobExtensions::Registry.new
    registry.register(
      Class.new(Sentry::JobExtensions::Extension) do
        define_method(:handles?) { |_job| true }
        hooks.each { |hook, body| define_method(hook, &body) }
      end.new(name: "test_backend")
    )
    described_class.new(integration: integration, origin: "auto.queue.test", registry: registry)
  end

  def scope
    Sentry.get_current_scope
  end

  def start_transaction(consumer, **options)
    scope.set_transaction_name("TestJob", source: :task)
    consumer.start_transaction(scope, job, **options)
  end

  def finished_transaction(consumer, **options)
    transaction = start_transaction(consumer, **options)
    consumer.finish_transaction(transaction, 200)
    sentry_events.last
  end

  def capture(consumer, exception = RuntimeError.new("boom"), **options)
    consumer.capture_exception(job, exception, **options)
    sentry_events.last
  end

  def enriching_consumer
    consumer(
      messaging_data: ->(job:) { { system: "backend", message_id: job.id, destination: job.queue, receive_latency: 42.5 } },
      retry_info: ->(job:) { { count: 3, will_retry: true } },
      scope_data: ->(job:) { { contexts: { backend: { "jid" => "backend-jid" } }, tags: { "backend.queue" => "low" }, extra: { size: 12 } } }
    )
  end

  let(:foreign_trace_id) { "a" * 32 }
  let(:foreign_trace_headers) { { "sentry-trace" => "#{foreign_trace_id}-#{"b" * 16}-1" } }

  before do
    perform_basic_setup do |config|
      config.traces_sample_rate = 1.0
      config.sdk_logger = Logger.new(string_io)
    end
    setup_sentry_test
  end

  after do
    teardown_sentry_test
  end

  describe "#start_transaction" do
    it "starts a queue.process transaction on the scope named after the scope's transaction" do
      transaction = start_transaction(consumer)

      expect(scope.get_span).to eq(transaction)
      expect(transaction.op).to eq("queue.process")
      expect(transaction.origin).to eq("auto.queue.test")
      expect(transaction.name).to eq("TestJob")
      expect(transaction.source).to eq(:task)
    end

    it "reuses the supplied transaction while applying the job's identity and messaging data" do
      started = enriching_consumer
      transaction = Sentry.start_transaction(name: "BeforeHandoff", op: "queue.process", origin: "auto.queue.previous", trace_id: foreign_trace_id)
      span_id = transaction.span_id
      start_timestamp = transaction.start_timestamp

      reused = start_transaction(started, transaction: transaction)
      started.finish_transaction(reused, 200)

      expect(reused).to equal(transaction)
      expect(scope.get_span).to equal(transaction)
      expect(reused.start_timestamp).to eq(start_timestamp)
      expect(sentry_events.size).to eq(1)
      event = sentry_events.last
      expect(event.transaction).to eq("TestJob")
      expect(event.transaction_info).to include(source: :task)
      expect(event.contexts[:trace]).to include(trace_id: foreign_trace_id, span_id: span_id, origin: "auto.queue.test")
      expect(event.contexts.dig(:trace, :data)).to include(
        "messaging.system" => "backend",
        "messaging.message.id" => "job-1",
        "messaging.message.retry.count" => 3
      )
    end

    it "records the extension's messaging data and retry count as span data" do
      event = finished_transaction(enriching_consumer)

      expect(event.contexts.dig(:trace, :data)).to include(
        "messaging.system" => "backend",
        "messaging.message.id" => "job-1",
        "messaging.destination.name" => "critical",
        "messaging.message.receive.latency" => 42.5,
        "messaging.message.retry.count" => 3
      )
    end

    it "lets the extension's messaging data win over the caller's and fills the rest from non-nil caller values" do
      partial_consumer = consumer(messaging_data: ->(job:) { { system: "backend", message_id: job.id } })

      event = finished_transaction(
        partial_consumer,
        messaging_data: { system: "caller", message_id: "caller-id", destination: "caller-queue", receive_latency: nil }
      )

      data = event.contexts.dig(:trace, :data)
      expect(data).to include(
        "messaging.system" => "backend",
        "messaging.message.id" => "job-1",
        "messaging.destination.name" => "caller-queue"
      )
      expect(data).not_to have_key("messaging.message.receive.latency")
    end

    it "uses the caller's default retry count when the extension reports no retry state" do
      expect(finished_transaction(consumer, default_retry_count: 7).contexts.dig(:trace, :data))
        .to include("messaging.message.retry.count" => 7)
    end

    it "evaluates a callable default retry count when the extension reports no retry state" do
      event = finished_transaction(consumer, default_retry_count: -> { 7 })

      expect(event.contexts.dig(:trace, :data)).to include("messaging.message.retry.count" => 7)
    end

    it "prefers the extension's retry count over the caller's default" do
      expect(finished_transaction(enriching_consumer, default_retry_count: 7).contexts.dig(:trace, :data))
        .to include("messaging.message.retry.count" => 3)
    end

    it "records only the caller's data when no registered extension handles the job" do
      unhandled = described_class.new(integration: integration, origin: "auto.queue.test", registry: Sentry::JobExtensions::Registry.new)

      event = finished_transaction(unhandled, default_retry_count: 7)

      expect(event.contexts.dig(:trace, :data)).to include("messaging.message.retry.count" => 7)
      expect(event.contexts.dig(:trace, :data)).not_to include("messaging.system")
    end

    it "continues the trace from the caller's trace headers" do
      transaction = start_transaction(consumer, trace_headers: foreign_trace_headers)

      expect(transaction.trace_id).to eq(foreign_trace_id)
    end

    it "continues the trace the extension extracts from the payload when the caller has no trace headers" do
      transaction = start_transaction(consumer(extract_trace_headers: ->(job:, payload:) { payload["headers"] }), trace_headers: {}, payload: { "headers" => foreign_trace_headers })

      expect(transaction.trace_id).to eq(foreign_trace_id)
    end

    it "prefers the caller's trace headers over the ones the extension extracts" do
      transaction = start_transaction(consumer(extract_trace_headers: ->(job:, payload:) { { "sentry-trace" => "#{"c" * 32}-#{"d" * 16}-1" } }), trace_headers: foreign_trace_headers, payload: {})

      expect(transaction.trace_id).to eq(foreign_trace_id)
    end

    it "keeps the scope's trace when there are no trace headers" do
      scope_trace_id = scope.propagation_context.trace_id

      start_transaction(consumer)

      expect(scope.propagation_context.trace_id).to eq(scope_trace_id)
    end

    it "starts a new trace on the scope without trace headers when told to always continue the trace" do
      scope_trace_id = scope.propagation_context.trace_id

      start_transaction(consumer, always_continue_trace: true)

      expect(scope.propagation_context.trace_id).not_to eq(scope_trace_id)
    end

    it "starts a new trace on the scope when the extension extracts no trace headers from the payload" do
      scope_trace_id = scope.propagation_context.trace_id

      start_transaction(consumer(extract_trace_headers: ->(job:, payload:) { {} }), payload: {})

      expect(scope.propagation_context.trace_id).not_to eq(scope_trace_id)
    end

    it "returns nil when tracing is disabled" do
      Sentry.configuration.traces_sample_rate = nil

      expect(start_transaction(enriching_consumer)).to be_nil
    end

    {
      "raise" => ->(**) { raise "hook exploded" },
      "return malformed data" => ->(**) { "malformed" }
    }.each do |behavior, body|
      it "starts the transaction without extension data when the hooks #{behavior}" do
        event = finished_transaction(consumer(messaging_data: body, retry_info: body, extract_trace_headers: body), payload: {})

        expect(event.contexts.dig(:trace, :status)).to eq("ok")
        expect(event.contexts.dig(:trace, :data).keys.grep(/\Amessaging\./)).to be_empty
        expect(string_io.string).to include("test_backend")
      end
    end
  end

  describe "#finish_transaction" do
    it "finishes the transaction with the status for the given HTTP status code" do
      started = consumer
      transaction = start_transaction(started)

      started.finish_transaction(transaction, 500)

      expect(sentry_events.last.contexts.dig(:trace, :status)).to eq("internal_error")
    end

    it "keeps the first completion status and sends the transaction only once" do
      started = consumer
      transaction = start_transaction(started)
      started.finish_transaction(transaction, 200)
      timestamp = transaction.timestamp

      started.finish_transaction(transaction, 500)

      expect(transaction.timestamp).to eq(timestamp)
      expect(transaction.status).to eq("ok")
      expect(sentry_events.size).to eq(1)
      expect(sentry_events.last.contexts.dig(:trace, :status)).to eq("ok")
    end

    it "ignores a missing transaction" do
      expect { consumer.finish_transaction(nil, 200) }.not_to raise_error
    end
  end

  describe "#apply_scope_data" do
    it "adds the extension's contexts, tags and extra to the scope" do
      enriching_consumer.apply_scope_data(scope, job)

      expect(scope.contexts[:backend]).to eq("jid" => "backend-jid")
      expect(scope.tags).to include("backend.queue" => "low")
      expect(scope.extra).to include(size: 12)
    end

    it "sets the user the extension supplies on the scope" do
      consumer(scope_data: ->(job:) { { user: { "id" => "42", "segment" => "beta" } } }).apply_scope_data(scope, job)

      expect(scope.user).to eq("id" => "42", "segment" => "beta")
    end

    it "leaves the scope unchanged when the hook fails" do
      consumer(scope_data: ->(job:) { raise "boom" }).apply_scope_data(scope, job)

      expect(scope.tags).to be_empty
      expect(scope.extra).to be_empty
    end
  end

  describe "#will_retry?" do
    it "reports whether the extension says the backend will retry the job" do
      expect(enriching_consumer.will_retry?(job)).to be(true)
      expect(consumer(retry_info: ->(job:) { { count: 3, will_retry: false } }).will_retry?(job)).to be(false)
    end

    it "reports no retry when the backend's retry state is unknown" do
      expect(consumer.will_retry?(job)).to be(false)
      expect(consumer(retry_info: ->(job:) { "malformed" }).will_retry?(job)).to be(false)
    end
  end

  describe "#report_exception?" do
    let(:exception) { RuntimeError.new("boom") }

    it "follows the extension's decision whether the backend will retry the job or not" do
      reporting = consumer(report_exception?: ->(job:, exception:) { true }, retry_info: ->(job:) { { count: 0, will_retry: true } })
      silent = consumer(report_exception?: ->(job:, exception:) { false }, retry_info: ->(job:) { { count: 0, will_retry: false } })

      expect(reporting.report_exception?(job, exception)).to be(true)
      expect(silent.report_exception?(job, exception)).to be(false)
    end

    it "reports only failures the backend will not retry when the extension does not decide" do
      expect(consumer.report_exception?(job, exception)).to be(true)
      expect(enriching_consumer.report_exception?(job, exception)).to be(false)
    end

    {
      "raises" => ->(**) { raise "hook exploded" },
      "returns malformed data" => ->(**) { "yes" }
    }.each do |behavior, body|
      it "falls back to the backend's retry state when the hook #{behavior}" do
        expect(consumer(report_exception?: body, retry_info: ->(job:) { { count: 0, will_retry: true } }).report_exception?(job, exception)).to be(false)
        expect(string_io.string).to include("test_backend")
      end
    end
  end

  describe "#capture_exception" do
    def error_consumer
      consumer(
        error_data: lambda do |job:, exception:|
          {
            contexts: { backend_error: { "retried" => true }, job: { "id" => "backend", "attempt" => 2 } },
            tags: { "backend.error" => "yes", queue: "backend-queue", job_id: "backend" },
            extra: { attempts: 2, size: 99 }
          }
        end
      )
    end

    it "captures the exception through the integration" do
      event = capture(consumer)

      expect(event.exception.values.last.type).to eq("RuntimeError")
      expect(event.exception.values.last.mechanism.type).to eq("test_jobs")
      expect(event.sdk[:name]).to eq("sentry.ruby.test_jobs")
    end

    it "adds the extension's error data without replacing values already on the scope" do
      scope.set_contexts(job: { "id" => "scope" })
      scope.set_tags(queue: "default")
      scope.set_extras(size: 12)

      event = capture(error_consumer)

      expect(event.contexts[:backend_error]).to eq("retried" => true)
      expect(event.contexts[:job]).to eq("id" => "scope", "attempt" => 2)
      expect(event.tags).to include("backend.error" => "yes", queue: "default")
      expect(event.extra).to include(attempts: 2, size: 12)
    end

    it "keeps existing extension and user context values while adding error-specific fields" do
      refining_consumer = consumer(
        scope_data: ->(job:) { { contexts: { job: { "id" => "backend", "args" => ["raw"] } } } },
        error_data: ->(job:, exception:) { { contexts: { job: { "args" => ["filtered"], "id" => "error", "attempt" => 2 } } } }
      )
      refining_consumer.apply_scope_data(scope, job)
      scope.set_contexts(job: { "id" => "user" })

      event = capture(refining_consumer)

      expect(event.contexts[:job]).to eq("id" => "user", "args" => ["raw"], "attempt" => 2)
    end

    it "lets the caller's contexts, tags and extra win over the extension's error data" do
      event = capture(error_consumer, contexts: { job: { "id" => "caller" } }, tags: { job_id: "caller" }, extra: { attempts: 5 })

      expect(event.contexts[:job]).to eq("id" => "caller")
      expect(event.tags).to include(job_id: "caller", "backend.error" => "yes")
      expect(event.extra).to include(attempts: 5)
    end

    it "lets caller tags and extra override extension values with equivalent string or symbol keys" do
      event = capture(error_consumer, tags: { "job_id" => "caller", :"backend.error" => "caller-error" }, extra: { "attempts" => 5 })

      expect(event.tags).to eq(job_id: "caller", queue: "backend-queue", "backend.error" => "caller-error")
      expect(event.extra).to eq(attempts: 5, size: 99)
      expect(event.to_json_compatible).to include(
        "tags" => { "job_id" => "caller", "queue" => "backend-queue", "backend.error" => "caller-error" },
        "extra" => { "attempts" => 5, "size" => 99 }
      )
    end

    it "captures the exception with the caller's data when the hook fails" do
      event = capture(consumer(error_data: ->(**) { raise "hook exploded" }), tags: { job_id: "caller" })

      expect(event.exception.values.last.type).to eq("RuntimeError")
      expect(event.tags).to eq(job_id: "caller")
    end
  end
end
