# frozen_string_literal: true

require "sentry/integrable"

module Sentry
  module TestJobsIntegration
    extend Sentry::Integrable

    register_integration name: "test_jobs", version: "1.0"
  end
end

RSpec.describe Sentry::JobExtensions::Extension do
  let(:job) { Struct.new(:id, :queue).new("job-1", "critical") }
  let(:exception) { RuntimeError.new("boom") }
  let(:string_io) { StringIO.new }
  let(:foreign_trace_id) { "a" * 32 }
  let(:foreign_trace_headers) { { "sentry-trace" => "#{foreign_trace_id}-#{"b" * 16}-1" } }

  def build_extension(**hooks)
    Class.new(described_class) do
      hooks.each { |hook, body| define_method(hook, &body) }
    end.new(name: :test_backend, integration: Sentry::TestJobsIntegration, origin: "auto.queue.test")
  end

  def enriching_extension
    build_extension(
      messaging_data: ->(job:, **) { { system: "backend", message_id: job.id, destination: job.queue, receive_latency: 42.5, retry_count: 3, body_size: 128 } },
      scope_data: ->(job:, **) { { contexts: { backend: { "jid" => "backend-jid" } }, tags: { "backend.queue" => "low" }, extra: { size: 12 } } }
    )
  end

  def tracing_extension(**hooks)
    build_extension(extract_trace_headers: ->(job:, trace_headers: {}, **) { trace_headers }, **hooks)
  end

  def scope
    Sentry.get_current_scope
  end

  def within_transaction
    transaction = Sentry.start_transaction(name: "parent", op: "test")
    scope.set_span(transaction)
    yield
  ensure
    transaction.finish
  end

  def publish_span
    sentry_events.last.spans.find { |span| span[:op] == "queue.publish" }
  end

  def finished_job(extension, **context)
    transaction = extension.start_job(scope: scope, job: job, **context)
    extension.finish_job(transaction: transaction, status: 200)
    sentry_events.last
  end

  def capture(extension, **options)
    extension.capture_exception(job: job, exception: exception, **options)
    sentry_events.last
  end

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

  describe "#initialize" do
    it "keeps the Symbol name as given" do
      expect(build_extension.name).to be(:test_backend)
    end

    it "rejects a name that is not a Symbol" do
      expect { described_class.new(name: "test_backend", integration: Sentry::TestJobsIntegration, origin: "auto.queue.test") }
        .to raise_error(ArgumentError, /must be a Symbol/)
      expect { described_class.new(name: nil, integration: Sentry::TestJobsIntegration, origin: "auto.queue.test") }
        .to raise_error(ArgumentError, /must be a Symbol/)
    end
  end

  describe "hooks" do
    let(:extension) { build_extension }
    let(:payload) { { "class" => "HardJob", "args" => [1] } }

    it "supplies no scope, error or messaging data by default" do
      expect(extension.scope_data(job: job)).to eq({})
      expect(extension.error_data(job: job, exception: exception)).to eq({})
      expect(extension.messaging_data(job: job)).to eq({})
      expect(extension.publish_messaging_data(job: job)).to eq({})
    end

    it "carries no trace headers and leaves the payload unchanged by default" do
      expect(extension.extract_trace_headers(job: job)).to eq({})
      expect(extension.inject_trace_headers(job: job, payload: payload, headers: { "sentry-trace" => "trace" })).to equal(payload)
    end

    it "reports an exception only when the backend will not retry the job" do
      expect(build_extension(will_retry?: ->(**) { false }).report_exception?(job: job, exception: exception)).to be(true)
      expect(build_extension(will_retry?: ->(**) { true }).report_exception?(job: job, exception: exception)).to be(false)
    end

    it "does not report exceptions the job integration retries by default" do
      expect(extension.report_retried_exception?(job: job, exception: exception)).to be(false)
    end

    it "uses the messaging data for the publish span unless overridden" do
      messaging = build_extension(messaging_data: ->(job:, **) { { system: "backend" } })

      expect(messaging.publish_messaging_data(job: job)).to eq(system: "backend")
    end

    it "ignores keywords a hook does not read" do
      expect(extension.scope_data(job: job, queue: "low")).to eq({})
      expect(extension.report_exception?(job: job, exception: exception, attempt: 2)).to be(true)
    end

    it "passes the keywords an integration supplies to the hooks that read them" do
      queue_aware = build_extension(scope_data: ->(job:, queue:, **) { { tags: { queue: queue } } })

      queue_aware.start_job(scope: scope, job: job, queue: "low")

      expect(scope.tags).to include(queue: "low")
    end
  end

  describe "#instrument_enqueue" do
    it "records a queue.publish span with the extension's identity and messaging data around the enqueue" do
      extension = build_extension(
        publish_description: ->(**) { "TestJob" },
        publish_messaging_data: ->(job:, **) { { system: "backend", message_id: job.id, destination: job.queue, retry_count: 3 } }
      )

      result = within_transaction { extension.instrument_enqueue(job: job) { :enqueued } }

      expect(result).to eq(:enqueued)
      expect(publish_span).to include(description: "TestJob", origin: "auto.queue.test")
      expect(publish_span[:data]).to include(
        "messaging.system" => "backend",
        "messaging.message.id" => "job-1",
        "messaging.destination.name" => "critical",
        "messaging.message.retry.count" => 3
      )
    end

    it "gives the publish span its own origin when the extension supplies one" do
      extension = build_extension(publish_span_origin: ->(**) { Sentry::Span::DEFAULT_SPAN_ORIGIN })

      within_transaction { extension.instrument_enqueue(job: job) { :enqueued } }

      expect(publish_span).to include(origin: "manual")
    end

    it "enqueues without a span when no transaction is active" do
      expect(build_extension.instrument_enqueue(job: job) { :enqueued }).to eq(:enqueued)
      expect(sentry_events).to be_empty
    end

    it "enqueues without a span when the extension does not record one" do
      extension = build_extension(record_publish_span?: ->(**) { false })

      result = within_transaction { extension.instrument_enqueue(job: job) { :enqueued } }

      expect(result).to eq(:enqueued)
      expect(publish_span).to be_nil
    end

    it "logs an instrumentation failure and enqueues the job exactly once" do
      failing = build_extension(publish_messaging_data: ->(**) { raise "boom from instrumentation" })
      enqueued = 0

      result = within_transaction { failing.instrument_enqueue(job: job) { enqueued += 1 } }

      expect(result).to eq(1)
      expect(enqueued).to eq(1)
      expect(string_io.string).to include("test_backend", "boom from instrumentation")
    end

    it "enqueues the job exactly once when a data hook returns something other than a Hash" do
      extension = build_extension(publish_messaging_data: ->(**) { nil })
      enqueued = 0

      within_transaction { extension.instrument_enqueue(job: job) { enqueued += 1 } }

      expect(enqueued).to eq(1)
      expect(publish_span).not_to be_nil
    end

    it "propagates a failing enqueue" do
      expect do
        within_transaction { build_extension.instrument_enqueue(job: job) { raise "boom from enqueue" } }
      end.to raise_error(RuntimeError, /boom from enqueue/)
    end
  end

  describe "#start_job" do
    it "starts a queue.process transaction on the scope named by the extension" do
      extension = build_extension(transaction_name: ->(**) { "TestJob" })

      transaction = extension.start_job(scope: scope, job: job)

      expect(scope.get_span).to eq(transaction)
      expect(transaction.op).to eq("queue.process")
      expect(transaction.origin).to eq("auto.queue.test")
      expect(transaction.name).to eq("TestJob")
      expect(transaction.source).to eq(:task)
    end

    it "adds the extension's contexts, tags and extra to the scope" do
      enriching_extension.start_job(scope: scope, job: job)

      expect(scope.contexts[:backend]).to eq("jid" => "backend-jid")
      expect(scope.tags).to include("backend.queue" => "low")
      expect(scope.extra).to include(size: 12)
    end

    it "sets the user the extension supplies on the scope" do
      build_extension(scope_data: ->(**) { { user: { "id" => "42", "segment" => "beta" } } }).start_job(scope: scope, job: job)

      expect(scope.user).to eq("id" => "42", "segment" => "beta")
    end

    it "records the extension's messaging data and retry count as span data" do
      event = finished_job(enriching_extension)

      expect(event.contexts.dig(:trace, :data)).to include(
        "messaging.system" => "backend",
        "messaging.message.id" => "job-1",
        "messaging.destination.name" => "critical",
        "messaging.message.receive.latency" => 42.5,
        "messaging.message.body.size" => 128,
        "messaging.message.retry.count" => 3
      )
    end

    it "records the known messaging data and skips keys outside the messaging attributes" do
      event = finished_job(build_extension(messaging_data: ->(job:, **) { { system: "backend", unknown_key: "value", destination: job.queue } }))

      expect(event.contexts.dig(:trace, :data)).to include("messaging.system" => "backend", "messaging.destination.name" => "critical")
      expect(event.contexts.dig(:trace, :data).values).not_to include("value")
    end

    it "records a messaging attribute the extension supplies with a nil value" do
      event = finished_job(build_extension(messaging_data: ->(**) { { system: "backend", retry_count: nil } }))

      expect(event.contexts.dig(:trace, :data)).to include("messaging.system" => "backend", "messaging.message.retry.count" => nil)
    end

    it "keeps the transaction and logs the failure when a hook raises" do
      failing = build_extension(
        scope_data: ->(**) { raise "broken scope data" },
        messaging_data: ->(**) { raise "broken messaging data" }
      )

      event = finished_job(failing)

      expect(event.contexts.dig(:trace, :op)).to eq("queue.process")
      expect(string_io.string).to include("broken scope data", "broken messaging data")
    end

    it "starts the transaction when data hooks return something other than a Hash" do
      extension = build_extension(
        scope_data: ->(**) { nil },
        extract_trace_headers: ->(**) { nil },
        messaging_data: ->(**) { "not a hash" }
      )

      event = finished_job(extension)

      expect(event.contexts.dig(:trace, :op)).to eq("queue.process")
      expect(string_io.string).to include("Job extension :test_backend failed to collect the messaging data")
    end

    it "starts the transaction and logs the failure when scope data holds values that are not Hashes" do
      extension = build_extension(scope_data: ->(**) { { contexts: { backend: nil }, tags: "low" } })

      event = finished_job(extension)

      expect(event.contexts.dig(:trace, :op)).to eq("queue.process")
      expect(string_io.string).to include("Job extension :test_backend failed to apply the scope data")
    end

    it "continues the trace described by the extracted trace headers" do
      transaction = tracing_extension.start_job(scope: scope, job: job, trace_headers: foreign_trace_headers)

      expect(transaction.trace_id).to eq(foreign_trace_id)
    end

    it "keeps the scope's trace when there are no trace headers" do
      scope_trace_id = scope.propagation_context.trace_id

      transaction = tracing_extension.start_job(scope: scope, job: job)

      expect(scope.propagation_context.trace_id).to eq(scope_trace_id)
      expect(transaction.parent_span_id).to be_nil
    end

    it "returns nil when tracing is disabled" do
      Sentry.configuration.traces_sample_rate = nil

      expect(enriching_extension.start_job(scope: scope, job: job)).to be_nil
    end

    context "when an extension collects latency only for sampled deliveries" do
      let(:job) { Struct.new(:id, :queue, :enqueued_at).new("job-1", "critical", Time.now - 5) }
      let(:sampling_extension) do
        tracing_extension(
          messaging_data: lambda do |job:, **|
            data = { system: "backend", message_id: job.id, destination: job.queue }
            data[:receive_latency] = (Time.now - job.enqueued_at) * 1_000 if Sentry.get_current_scope.get_span&.sampled
            data
          end
        )
      end

      it "records latency for a sampled delivery when the caller is unsampled" do
        scope.set_span(Sentry.start_transaction(name: "worker", op: "worker", sampled: false))

        event = finished_job(sampling_extension, trace_headers: foreign_trace_headers)

        expect(event.contexts.dig(:trace, :data)).to include("messaging.message.receive.latency" => a_kind_of(Numeric))
      end

      it "omits latency from an unsampled delivery's error when the caller is sampled" do
        scope.set_span(Sentry.start_transaction(name: "worker", op: "worker", sampled: true))
        headers = { "sentry-trace" => "#{foreign_trace_id}-#{"b" * 16}-0" }
        transaction = sampling_extension.start_job(scope: scope, job: job, trace_headers: headers)

        event = capture(sampling_extension)
        sampling_extension.finish_job(transaction: transaction, status: 500)

        expect(event.contexts.dig(:trace, :data)).to include(
          "messaging.system" => "backend",
          "messaging.message.id" => job.id,
          "messaging.destination.name" => job.queue
        )
        expect(event.contexts.dig(:trace, :data)).not_to have_key("messaging.message.receive.latency")
      end
    end
  end

  describe "#finish_job" do
    let(:extension) { build_extension }

    it "finishes the transaction with the status for the given HTTP status code" do
      transaction = extension.start_job(scope: scope, job: job)

      extension.finish_job(transaction: transaction, status: 500)

      expect(sentry_events.last.contexts.dig(:trace, :status)).to eq("internal_error")
    end

    it "keeps the first completion status and sends the transaction only once" do
      transaction = extension.start_job(scope: scope, job: job)
      extension.finish_job(transaction: transaction, status: 200)

      extension.finish_job(transaction: transaction, status: 500)

      expect(transaction.status).to eq("ok")
      expect(sentry_events.size).to eq(1)
    end

    it "ignores a missing transaction" do
      expect { extension.finish_job(transaction: nil, status: 200) }.not_to raise_error
    end
  end

  describe "#capture_exception" do
    def error_extension
      build_extension(
        error_data: lambda do |**|
          {
            contexts: { backend_error: { "retried" => true }, job: { "id" => "backend", "attempt" => 2 } },
            tags: { "backend.error" => "yes", queue: "backend-queue", job_id: "backend" },
            extra: { attempts: 2, size: 99 }
          }
        end
      )
    end

    it "captures the exception through the extension's integration" do
      event = capture(build_extension)

      expect(event.exception.values.last.type).to eq("RuntimeError")
      expect(event.exception.values.last.mechanism.type).to eq("test_jobs")
      expect(event.sdk[:name]).to eq("sentry.ruby.test_jobs")
    end

    it "adds the extension's error data without replacing values already on the scope" do
      scope.set_contexts(job: { "id" => "scope" })
      scope.set_tags(queue: "default")
      scope.set_extras(size: 12)

      event = capture(error_extension)

      expect(event.contexts[:backend_error]).to eq("retried" => true)
      expect(event.contexts[:job]).to eq("id" => "scope", "attempt" => 2)
      expect(event.tags).to include("backend.error" => "yes", queue: "default")
      expect(event.extra).to include(attempts: 2, size: 12)
    end

    it "lets the caller's contexts, tags and extra win over the extension's error data" do
      event = capture(error_extension, contexts: { job: { "id" => "caller" } }, tags: { job_id: "caller" }, extra: { attempts: 5 })

      expect(event.contexts[:job]).to eq("id" => "caller")
      expect(event.tags).to include(job_id: "caller", "backend.error" => "yes")
      expect(event.extra).to include(attempts: 5)
    end

    it "lets the caller's contexts, tags and extra win over values already on the scope" do
      scope.set_contexts(job: { "id" => "scope" })
      scope.set_tags(queue: "default")
      scope.set_extras(size: 12)

      event = capture(error_extension, contexts: { job: { "id" => "caller" } }, tags: { queue: "caller" }, extra: { size: 5 })

      expect(event.contexts[:job]).to eq("id" => "caller")
      expect(event.tags).to include(queue: "caller")
      expect(event.extra).to include(size: 5)
    end

    it "captures the exception with the caller's data through its own integration when a hook raises" do
      failing = build_extension(error_data: ->(**) { raise "broken error data" })

      event = capture(failing, tags: { job_id: "caller" })

      expect(event.exception.values.last.mechanism.type).to eq("test_jobs")
      expect(event.tags).to include(job_id: "caller")
      expect(string_io.string).to include("broken error data")
    end

    it "captures the exception with the caller's data when the error data hook returns nil values" do
      extension = build_extension(error_data: ->(**) { { contexts: { backend: nil }, tags: nil, extra: nil } })

      event = capture(extension, tags: { job_id: "caller" })

      expect(event.exception.values.last.type).to eq("RuntimeError")
      expect(event.tags).to include(job_id: "caller")
    end

    it "captures the exception with the caller's data when the error data hook returns something other than a Hash" do
      event = capture(build_extension(error_data: ->(**) { nil }), tags: { job_id: "caller" })

      expect(event.exception.values.last.type).to eq("RuntimeError")
      expect(event.tags).to include(job_id: "caller")
    end

    it "captures nothing and raises nothing when the SDK is not initialized" do
      reset_sentry_globals!

      result = error_extension.capture_exception(job: job, exception: exception, tags: { job_id: "caller" })

      expect(result).to be_nil
    end
  end
end
