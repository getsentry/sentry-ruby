# frozen_string_literal: true

RSpec.describe Sentry::JobExtensions::Producer do
  let(:job) { Struct.new(:id, :queue).new("job-1", "critical") }
  let(:string_io) { StringIO.new }

  def producer(origin: nil, **hooks)
    registry = Sentry::JobExtensions::Registry.new
    registry.register(
      Class.new(Sentry::JobExtensions::Extension) do
        define_method(:handles?) { |_job| true }
        hooks.each { |hook, body| define_method(hook, &body) }
      end.new(name: "test_backend")
    )
    described_class.new(origin: origin, registry: registry)
  end

  def enriching_producer(origin: nil)
    producer(
      origin: origin,
      messaging_data: ->(job:) { { system: "backend", message_id: job.id, destination: job.queue, receive_latency: 42.5, body_size: 128 } },
      retry_info: ->(job:) { { count: 3, will_retry: true } }
    )
  end

  def within_transaction
    transaction = Sentry.start_transaction(name: "parent", op: "test")
    Sentry.get_current_scope.set_span(transaction)
    yield
  ensure
    transaction.finish
  end

  def publish_span
    sentry_events.last.spans.find { |span| span[:op] == "queue.publish" }
  end

  def record_span(producer, **options, &enqueue)
    producer.record_span(job, description: "TestJob", **options, &(enqueue || -> { :enqueued }))
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

  describe "#record_span" do
    it "records a queue.publish span with the extension's messaging data and retry count around the enqueue" do
      result = within_transaction { record_span(enriching_producer(origin: "auto.queue.test")) }

      expect(result).to eq(:enqueued)
      expect(publish_span).to include(description: "TestJob", origin: "auto.queue.test")
      expect(publish_span[:data]).to include(
        "messaging.system" => "backend",
        "messaging.message.id" => "job-1",
        "messaging.destination.name" => "critical",
        "messaging.message.receive.latency" => 42.5,
        "messaging.message.body.size" => 128,
        "messaging.message.retry.count" => 3
      )
    end

    it "lets the caller's messaging data win over the extension's" do
      within_transaction do
        record_span(enriching_producer, messaging_data: { system: "caller", message_id: "caller-id" })
      end

      expect(publish_span[:data]).to include(
        "messaging.system" => "caller",
        "messaging.message.id" => "caller-id",
        "messaging.destination.name" => "critical"
      )
    end

    it "applies only the requested keys of the extension's messaging data" do
      within_transaction do
        record_span(enriching_producer, extension_messaging_keys: %i[message_id destination])
      end

      expect(publish_span[:data]).to include("messaging.message.id" => "job-1", "messaging.destination.name" => "critical")
      expect(publish_span[:data]).not_to include("messaging.system", "messaging.message.receive.latency")
    end

    it "falls back to the caller's retry count when the extension has no retry info" do
      within_transaction { record_span(producer, default_retry_count: 2) }

      expect(publish_span[:data]).to include("messaging.message.retry.count" => 2)
    end

    it "records no retry count when the caller opts out" do
      within_transaction { record_span(enriching_producer, retry_count: false) }

      expect(publish_span[:data]).not_to include("messaging.message.retry.count")
    end

    it "degrades a failing extension hook to its neutral result" do
      within_transaction { record_span(producer(messaging_data: ->(job:) { raise "boom" }, retry_info: ->(job:) { :malformed }), default_retry_count: 1) }

      expect(publish_span[:data]).to include("messaging.message.retry.count" => 1)
      expect(publish_span[:data]).not_to include("messaging.message.id")
    end

    it "enqueues without a span when no transaction is active" do
      expect(record_span(enriching_producer)).to eq(:enqueued)
      expect(sentry_events).to be_empty
    end

    context "when recording the span raises" do
      before do
        allow(Sentry).to receive(:with_child_span).and_raise(StandardError, "boom from instrumentation")
      end

      it "propagates the failure without enqueueing when the caller wants no isolation" do
        enqueued = 0

        expect do
          within_transaction { record_span(enriching_producer) { enqueued += 1 } }
        end.to raise_error(StandardError, /boom from instrumentation/)
        expect(enqueued).to eq(0)
      end

      it "reports the failure to the caller and enqueues once when the caller wants isolation" do
        errors = []
        enqueued = 0

        result = within_transaction do
          record_span(enriching_producer, on_instrumentation_error: ->(e) { errors << e }) { enqueued += 1 }
        end

        expect(result).to eq(1)
        expect(enqueued).to eq(1)
        expect(errors.map(&:message)).to eq(["boom from instrumentation"])
      end
    end

    it "re-raises a failing enqueue without reporting it as an instrumentation failure" do
      errors = []

      expect do
        within_transaction do
          record_span(enriching_producer, on_instrumentation_error: ->(e) { errors << e }) { raise "boom from enqueue" }
        end
      end.to raise_error(RuntimeError, /boom from enqueue/)
      expect(errors).to be_empty
    end
  end

  describe "#inject_trace_headers" do
    let(:payload) { { "job_class" => "TestJob" } }
    let(:headers) { { "sentry-trace" => "trace" } }

    it "returns the payload the extension built with the headers" do
      extension_producer = producer(inject_trace_headers: ->(job:, payload:, headers:) { payload.merge("trace" => headers) })

      expect(extension_producer.inject_trace_headers(job, payload, headers)).to eq(
        "job_class" => "TestJob", "trace" => headers
      )
    end

    it "returns the payload unchanged when the extension fails" do
      failing_producer = producer(inject_trace_headers: ->(job:, payload:, headers:) { raise "boom" })

      expect(failing_producer.inject_trace_headers(job, payload, headers)).to equal(payload)
      expect(string_io.string).to include("failed in inject_trace_headers")
    end
  end
end
