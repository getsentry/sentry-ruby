# frozen_string_literal: true

require_relative "support/rails_app"
require "active_job/railtie"
require "sidekiq/api"

RSpec.describe "ActiveJob jobs on Sidekiq" do
  let(:sidekiq_adapter) { "ActiveJob::QueueAdapters::SidekiqAdapter" }
  let(:processor) { new_processor }
  let(:transport) { Sentry.get_current_client.transport }
  let(:traces_sample_rate) { 1.0 }

  let(:parity_job) do
    stub_const("ParityJob", Class.new(ActiveJob::Base) do
      self.queue_adapter = :sidekiq
      queue_as :events

      def perform(*); end
    end)
  end

  let(:reporting_job) do
    stub_const("ReportingParityJob", Class.new(ActiveJob::Base) do
      self.queue_adapter = :sidekiq

      def perform
        Sentry.capture_message("reported from the job")
      end
    end)
  end

  before do
    sample_rate = traces_sample_rate
    make_basic_app { |config| config.traces_sample_rate = sample_rate }
  end

  def enqueued_at
    WITH_SIDEKIQ_8 ? now_in_ms : Time.now.to_f
  end

  def sidekiq_message(job_class, *arguments, **attributes)
    job = job_class.new(*arguments)
    {
      "class" => ActiveJob::QueueAdapters::SidekiqAdapter::JobWrapper.to_s,
      "wrapped" => job_class.name,
      "queue" => job.queue_name,
      "args" => [job.serialize],
      "jid" => SecureRandom.hex(12),
      "retry" => true,
      "created_at" => enqueued_at,
      "enqueued_at" => enqueued_at
    }.merge(attributes.transform_keys(&:to_s))
  end

  def skip_sidekiq_adapter(skipped)
    adapters = Sentry.configuration.rails.skippable_job_adapters
    skipped ? adapters |= [sidekiq_adapter] : adapters -= [sidekiq_adapter]
    Sentry.configuration.rails.skippable_job_adapters = adapters
  end

  def process(message, adapter_skipped:)
    skip_sidekiq_adapter(adapter_skipped)
    transport.events.clear
    process_work(processor, Sidekiq::BasicFetch::UnitOfWork.new("queue:#{message["queue"]}", Sidekiq.dump_json(message)))
    transport.events.dup
  end

  def consumer_transactions(events)
    events.select { |event| event.is_a?(Sentry::TransactionEvent) && event.contexts.dig(:trace, :op) == "queue.process" }
  end

  def consumer_transaction(message, adapter_skipped:)
    consumer_transactions(process(message, adapter_skipped: adapter_skipped)).first
  end

  context "with the transaction sentry-sidekiq sends when the adapter is skipped" do
    let(:message) do
      sidekiq_message(
        parity_job,
        queue: "retry_events",
        tags: ["marvel", "dc"],
        retry_count: 2,
        sentry_user: { "id" => "42", "segment" => "beta" }
      )
    end

    let(:sidekiq_transactions) { consumer_transactions(process(message, adapter_skipped: true)) }
    let(:active_job_transactions) { consumer_transactions(process(message, adapter_skipped: false)) }
    let(:sidekiq_transaction) { sidekiq_transactions.first }
    let(:active_job_transaction) { active_job_transactions.first }

    it "sends one transaction with the same name and origin when the adapter is not skipped" do
      expect(sidekiq_transactions.size).to eq(1)
      expect(active_job_transactions.size).to eq(1)
      expect(sidekiq_transaction.transaction).to eq("Sidekiq/ParityJob")
      expect(active_job_transaction.transaction).to eq(sidekiq_transaction.transaction)
      expect(active_job_transaction.transaction_info).to eq(sidekiq_transaction.transaction_info)
      expect(active_job_transaction.contexts.dig(:trace, :origin)).to eq(sidekiq_transaction.contexts.dig(:trace, :origin))
    end

    it "sends the same sidekiq context, tags and user, plus the active_job context, when the adapter is not skipped" do
      expect(active_job_transaction.contexts[:sidekiq]).to eq(sidekiq_transaction.contexts[:sidekiq])
      expect(active_job_transaction.tags).to include(sidekiq_transaction.tags)
      expect(active_job_transaction.user).to eq(sidekiq_transaction.user)
      expect(active_job_transaction.contexts[:active_job]).to include(job_class: "ParityJob", queue: "events")
    end

    it "sends the same messaging data and retry count when the adapter is not skipped" do
      latency = "messaging.message.receive.latency"
      sidekiq_data = sidekiq_transaction.contexts.dig(:trace, :data)
      active_job_data = active_job_transaction.contexts.dig(:trace, :data)

      expect(active_job_data).to include(sidekiq_data.except(latency))
      expect(active_job_data[latency]).to be_within(1000).of(sidekiq_data[latency])
    end
  end

  [nil, 0.0, 1.0].each do |sample_rate|
    context "with incoming baggage at sample rate #{sample_rate.inspect}" do
      let(:traces_sample_rate) { sample_rate }

      it "matches native trace and baggage propagation when the adapter is not skipped" do
        job_class = stub_const("PropagationParityJob", Class.new(ActiveJob::Base) do
          self.queue_adapter = :sidekiq

          def perform
            Sentry.capture_message("propagated", extra: { headers: Sentry.get_trace_propagation_headers })
          end
        end)
        trace_id = "a" * 32
        headers = {
          "sentry-trace" => "#{trace_id}-#{"b" * 16}-1",
          "baggage" => "sentry-trace_id=#{trace_id},sentry-release=upstream,sentry-public_key=12345"
        }

        message = sidekiq_message(job_class, trace_propagation_headers: headers)
        native_event = process(message, adapter_skipped: true).grep(Sentry::ErrorEvent).first
        active_job_event = process(message, adapter_skipped: false).grep(Sentry::ErrorEvent).first

        expect(active_job_event.contexts[:trace].slice(:trace_id, :parent_span_id))
          .to eq(native_event.contexts[:trace].slice(:trace_id, :parent_span_id))
        expect(active_job_event.extra[:headers]["sentry-trace"].split("-").first)
          .to eq(native_event.extra[:headers]["sentry-trace"].split("-").first)
        expect(active_job_event.extra[:headers]["baggage"]).to eq(native_event.extra[:headers]["baggage"])
      end
    end
  end

  context "without trace propagation headers when tracing is disabled" do
    let(:traces_sample_rate) { nil }

    def reported_trace_id(adapter_skipped:)
      events = process(sidekiq_message(reporting_job), adapter_skipped: adapter_skipped)
      events.find { |event| event.is_a?(Sentry::ErrorEvent) }.contexts.dig(:trace, :trace_id)
    end

    it "starts a new trace for the job instead of keeping the worker's, whether the adapter is skipped or not" do
      worker_trace_id = Sentry.get_main_hub.current_scope.propagation_context.trace_id

      expect(reported_trace_id(adapter_skipped: true)).not_to eq(worker_trace_id)
      expect(reported_trace_id(adapter_skipped: false)).not_to eq(worker_trace_id)
    end
  end

  context "when the job fails" do
    let(:failing_job) do
      stub_const("FailingParityJob", Class.new(ActiveJob::Base) do
        self.queue_adapter = :sidekiq
        queue_as :events

        def perform(*)
          raise "job failed"
        end
      end)
    end

    def error_events(events)
      events.select { |event| event.is_a?(Sentry::ErrorEvent) }
    end

    def reported_events(adapter_skipped:, retry_counts:, **attributes)
      retry_counts.map do |retry_count|
        message = sidekiq_message(failing_job, retry_count: retry_count, **attributes)
        error_events(process(message, adapter_skipped: adapter_skipped))
      end
    end

    def expect_same_reported_attempts(retry_counts:, **attributes)
      sidekiq_events = reported_events(adapter_skipped: true, retry_counts: retry_counts, **attributes)
      active_job_events = reported_events(adapter_skipped: false, retry_counts: retry_counts, **attributes)

      expect(active_job_events.map(&:size)).to eq(sidekiq_events.map(&:size))
      expect(sidekiq_events.map(&:size).uniq).to contain_exactly(0, 1)
      expect(active_job_events.flatten).to all(satisfy { |event| event.contexts.key?(:active_job) })
    end

    context "with the error event sentry-sidekiq sends when the adapter is skipped" do
      let(:message) do
        sidekiq_message(
          failing_job,
          { "sku" => "abc" },
          queue: "retry_events",
          tags: ["marvel"],
          sentry_user: { "id" => "42" }
        )
      end

      let(:sidekiq_events) { error_events(process(message, adapter_skipped: true)) }
      let(:active_job_events) { error_events(process(message, adapter_skipped: false)) }
      let(:sidekiq_event) { sidekiq_events.first }
      let(:active_job_event) { active_job_events.first }

      it "captures it once under the sidekiq integration with the same transaction name when the adapter is not skipped" do
        expect(sidekiq_events.size).to eq(1)
        expect(active_job_events.size).to eq(1)
        expect(active_job_event.exception.values.first.mechanism.type).to eq("sidekiq")
        expect(active_job_event.transaction).to eq(sidekiq_event.transaction)
        expect(active_job_event.transaction_info).to eq(sidekiq_event.transaction_info)
      end

      it "sends the same tags, user and filtered sidekiq context, plus the ActiveJob data, when the adapter is not skipped" do
        expect(active_job_event.tags).to include(sidekiq_event.tags)
        expect(active_job_event.user).to eq(sidekiq_event.user)
        expect(active_job_event.contexts[:sidekiq]).to eq(sidekiq_event.contexts[:sidekiq])
        expect(active_job_event.contexts[:active_job]).to include(job_class: "FailingParityJob", queue: "events")
        expect(active_job_event.extra).to include(active_job: "FailingParityJob")
      end
    end

    [false, true].each do |report_after_retries|
      [true, false].each do |adapter_skipped|
        it "clears the failed delivery scope with report_after_job_retries=#{report_after_retries} and adapter_skipped=#{adapter_skipped}" do
          Sentry.configuration.sidekiq.report_after_job_retries = report_after_retries
          message = sidekiq_message(failing_job, retry: 2)
          hub = Sentry.get_current_hub
          Sentry.set_tags(worker: "outside")
          Sentry.set_user(id: "worker-user")
          Sentry.add_breadcrumb(Sentry::Breadcrumb.new(message: "worker context"))

          events = process(message, adapter_skipped: adapter_skipped)

          expect(error_events(events).size).to eq(report_after_retries ? 0 : 1)
          expect(Sentry.get_current_scope.tags).to be_empty
          expect(Sentry.get_current_scope.user).to be_empty
          expect(Sentry.get_current_scope.breadcrumbs).to be_empty
          expect(Sentry.get_current_scope.get_span).to be_nil
          expect(hub.current_scope.tags).to eq(worker: "outside")
        end
      end
    end

    it "restores the payload while leaving the failed delivery scope for the error handler" do
      skip_sidekiq_adapter(false)
      message = sidekiq_message(failing_job, queue: "retry_events")
      original_args = message["args"]
      original_payload = Marshal.load(Marshal.dump(original_args))
      hub = Sentry.get_current_hub
      Sentry.set_tags(worker: "outside")

      expect do
        Sentry::Sidekiq::SentryContextServerMiddleware.new.call(nil, message, "retry_events") do
          ActiveJob::Base.execute(message["args"].first)
        end
      end.to raise_error(RuntimeError, "job failed")

      expect(message["args"]).to equal(original_args)
      expect(message["args"]).to eq(original_payload)
      expect(Sentry.get_current_scope.tags).to include(queue: "retry_events", jid: message["jid"])
      expect(hub.current_scope.tags).to eq(worker: "outside")
    end

    context "with config.report_after_job_retries = true" do
      before { Sentry.configuration.sidekiq.report_after_job_retries = true }

      it "reports the same attempts whether the adapter is skipped or not when retry is a limit" do
        expect_same_reported_attempts(retry: 3, retry_counts: [nil, 0, 1, 2])
      end

      context "when Sidekiq sets max_retries" do
        let(:sidekiq_options) { WITH_SIDEKIQ_7 ? Sidekiq.default_configuration : Sidekiq.options }

        around do |example|
          previous_max_retries = sidekiq_options[:max_retries] || Sidekiq::JobRetry::DEFAULT_MAX_RETRY_ATTEMPTS
          sidekiq_options[:max_retries] = 3
          example.run
        ensure
          sidekiq_options[:max_retries] = previous_max_retries
        end

        it "reports the same attempts whether the adapter is skipped or not" do
          expect_same_reported_attempts(retry: true, retry_counts: [nil, 0, 1, 2])
        end
      end
    end

    context "with config.report_only_dead_jobs = true" do
      before { Sentry.configuration.sidekiq.report_only_dead_jobs = true }

      it "reports the same attempts whether the adapter is skipped or not" do
        sidekiq_events = [{}, { dead: false }].flat_map do |attributes|
          reported_events(adapter_skipped: true, retry_counts: [nil], retry: 0, **attributes)
        end
        active_job_events = [{}, { dead: false }].flat_map do |attributes|
          reported_events(adapter_skipped: false, retry_counts: [nil], retry: 0, **attributes)
        end

        expect(active_job_events.map(&:size)).to eq(sidekiq_events.map(&:size))
        expect(sidekiq_events.map(&:size)).to eq([1, 0])
        expect(active_job_events.flatten).to all(satisfy { |event| event.contexts.key?(:active_job) })
      end
    end

    context "with attempt_threshold" do
      it "reports the same attempts whether the adapter is skipped or not" do
        expect_same_reported_attempts(attempt_threshold: 3, retry_counts: [nil, 0, 1, 2])
      end

      it "reports the same attempts whether the adapter is skipped or not when the retry limit is below the threshold" do
        expect_same_reported_attempts(attempt_threshold: 3, retry: 1, retry_counts: [nil, 0])
      end
    end

    context "with ActiveJob retry_on and discard_on" do
      let(:retried_error) { stub_const("RetriedParityError", Class.new(StandardError)) }
      let(:discarded_error) { stub_const("DiscardedParityError", Class.new(StandardError)) }

      let(:retrying_job) do
        error = retried_error
        stub_const("RetryingParityJob", Class.new(ActiveJob::Base) do
          self.queue_adapter = :sidekiq
          retry_on error, attempts: 2, wait: 0

          define_method(:perform) { raise error }
        end)
      end

      let(:discarding_job) do
        error = discarded_error
        stub_const("DiscardingParityJob", Class.new(ActiveJob::Base) do
          self.queue_adapter = :sidekiq
          discard_on error

          define_method(:perform) { raise error }
        end)
      end

      def message_after_executions(job_class, error, executions)
        message = sidekiq_message(job_class)
        message["args"].first.merge!(
          "executions" => executions,
          "exception_executions" => { [error].to_s => executions }
        )
        message
      end

      def reported_executions(job_class, error, adapter_skipped:)
        [0, 1].map do |executions|
          message = message_after_executions(job_class, error, executions)
          error_events(process(message, adapter_skipped: adapter_skipped))
        end
      end

      it "reports a retry_on job at the same executions whether the adapter is skipped or not" do
        sidekiq_events = reported_executions(retrying_job, retried_error, adapter_skipped: true)
        active_job_events = reported_executions(retrying_job, retried_error, adapter_skipped: false)

        expect(active_job_events.map(&:size)).to eq(sidekiq_events.map(&:size))
        expect(sidekiq_events.map(&:size)).to eq([0, 1])
        expect(active_job_events.flatten).to all(satisfy { |event| event.contexts.key?(:active_job) })
      end

      context "with config.rails.active_job_report_on_retry_error = true" do
        before do
          retrying_job
          sample_rate = traces_sample_rate
          make_basic_app do |config|
            config.traces_sample_rate = sample_rate
            config.rails.active_job_report_on_retry_error = true
          end
        end

        it "reports a retry_on job at the same executions whether the adapter is skipped or not" do
          sidekiq_events = reported_executions(retrying_job, retried_error, adapter_skipped: true)

          expect(reported_executions(retrying_job, retried_error, adapter_skipped: false).map(&:size)).to eq(sidekiq_events.map(&:size))
          expect(sidekiq_events.map(&:size)).to eq([0, 1])
        end
      end

      it "reports a discard_on job at the same executions whether the adapter is skipped or not" do
        sidekiq_events = reported_executions(discarding_job, discarded_error, adapter_skipped: true)

        expect(reported_executions(discarding_job, discarded_error, adapter_skipped: false).map(&:size)).to eq(sidekiq_events.map(&:size))
        expect(sidekiq_events.map(&:size)).to eq([0, 0])
      end
    end
  end

  context "when job deserialization raises outside StandardError" do
    [LoadError, SystemStackError].each do |exception_class|
      it "preserves delivery context and the incoming trace for #{exception_class}" do
        job_class = Class.new(ActiveJob::Base) do
          self.queue_adapter = :sidekiq

          define_method(:deserialize) do |payload|
            super(payload)
            raise exception_class, "job deserialization failed"
          end

          def perform; end
        end
        stub_const("DeserializationFailureParityJob", job_class)
        message = sidekiq_message(
          job_class, retry: false, queue: "delivery", tags: ["marvel"],
          sentry_user: { "id" => "42" },
          trace_propagation_headers: { "sentry-trace" => "#{"a" * 32}-#{"b" * 16}-1" }
        )
        Sentry.set_tags(worker: "outside")
        hub = Sentry.get_current_hub

        expect { process(message, adapter_skipped: false) }.to raise_error(exception_class, "job deserialization failed")

        errors = transport.events.grep(Sentry::ErrorEvent)
        expect(errors.size).to eq(1)
        expect(errors.first.tags).to include(queue: "delivery", jid: message["jid"], "sidekiq.marvel": true)
        expect(errors.first.user).to include("id" => "42")
        expect(errors.first.contexts.dig(:trace, :trace_id)).to eq("a" * 32)
        expect(Sentry.get_current_scope.tags).to be_empty
        expect(hub.current_scope.tags).to eq(worker: "outside")
      end
    end
  end

  context "when the queued ActiveJob class cannot be loaded" do
    let(:traces_sample_rate) { nil }

    [nil, 1.0].each do |sample_rate|
      it "preserves native error enrichment and the incoming trace at sample rate #{sample_rate.inspect}" do
        Sentry.configuration.traces_sample_rate = sample_rate
        worker_transaction = Sentry.start_transaction(name: "worker", op: "test")
        Sentry.get_main_hub.current_scope.set_span(worker_transaction) if worker_transaction

        message = sidekiq_message(
          parity_job,
          retry: false,
          tags: ["marvel"],
          sentry_user: { "id" => "42" },
          trace_propagation_headers: { "sentry-trace" => "#{"a" * 32}-#{"b" * 16}-0" }
        )
        message["wrapped"] = "RemovedJob"
        message["args"].first["job_class"] = "RemovedJob"

        native_errors = process(message, adapter_skipped: true).grep(Sentry::ErrorEvent)
        active_job_errors = process(message, adapter_skipped: false).grep(Sentry::ErrorEvent)

        expect(native_errors.size).to eq(1)
        expect(active_job_errors.size).to eq(1)
        expect(active_job_errors.first.tags).to include(native_errors.first.tags)
        expect(active_job_errors.first.user).to eq(native_errors.first.user)
        expect(active_job_errors.first.contexts.dig(:trace, :trace_id)).to eq("a" * 32)
      end
    end

    it "records one failed consumer transaction when the queued job class is missing" do
      Sentry.configuration.traces_sample_rate = 1.0
      message = sidekiq_message(
        parity_job, retry: false, queue: "delivery",
        trace_propagation_headers: { "sentry-trace" => "#{"a" * 32}-#{"b" * 16}-1" }
      )
      message["wrapped"] = "RemovedJob"
      message["args"].first["job_class"] = "RemovedJob"

      [true, false].each do |adapter_skipped|
        events = process(message, adapter_skipped: adapter_skipped)
        transactions = consumer_transactions(events)
        errors = events.grep(Sentry::ErrorEvent)

        expect(transactions.size).to eq(1)
        expect(errors.size).to eq(1)
        expect(transactions.first.transaction).to eq("Sidekiq/RemovedJob")
        expect(transactions.first.contexts.dig(:trace, :status)).to eq("internal_error")
        expect(transactions.first.contexts.dig(:trace, :trace_id)).to eq("a" * 32)
        expect(transactions.first.contexts.dig(:trace, :data)).to include(
          "messaging.message.id" => message["jid"], "messaging.destination.name" => "delivery"
        )
        expect(errors.first.contexts.dig(:trace, :span_id)).to eq(transactions.first.contexts.dig(:trace, :span_id))
      end
    end

    it "preserves the payload and delivery scope when loading the job fails" do
      skip_sidekiq_adapter(false)
      message = sidekiq_message(parity_job, retry: false)
      message["args"].first["job_class"] = "RemovedJob"
      original_args = message["args"]
      original_payload = Marshal.load(Marshal.dump(original_args))
      hub = Sentry.get_current_hub
      Sentry.set_tags(worker: "outside")

      expect do
        Sentry::Sidekiq::SentryContextServerMiddleware.new.call(nil, message, "events") do
          ActiveJob::Base.execute(message["args"].first)
        end
      end.to raise_error(NameError)

      expect(message["args"]).to equal(original_args)
      expect(message["args"]).to eq(original_payload)
      expect(Sentry.get_current_scope.tags).to include(queue: "events", jid: message["jid"])
      expect(hub.current_scope.tags).to eq(worker: "outside")
    end
  end

  context "with a separate running Sidekiq configuration", skip: !WITH_SIDEKIQ_7 do
    let(:running_config) do
      Sidekiq::Config.new(max_retries: 5).tap do |config|
        config.logger = Logger.new(nil)
        config.error_handlers.clear
        config.error_handlers << Sentry::Sidekiq::ErrorHandler.new
        config.server_middleware { |chain| chain.add Sentry::Sidekiq::SentryContextServerMiddleware }
      end
    end
    let(:processor) { Sidekiq::Processor.new(running_config.default_capsule) }
    let(:failing_job) do
      stub_const("ConfigParityJob", Class.new(ActiveJob::Base) do
        self.queue_adapter = :sidekiq

        def perform
          raise "job failed"
        end
      end)
    end

    around do |example|
      previous_max_retries = Sidekiq.default_configuration[:max_retries]
      Sidekiq.default_configuration[:max_retries] = 3
      example.run
    ensure
      Sidekiq.default_configuration[:max_retries] = previous_max_retries
    end

    [true, false].each do |adapter_skipped|
      context "when the Sidekiq adapter is #{adapter_skipped ? 'skipped' : 'handled by ActiveJob'}" do
        it "uses the running retry limit when reporting only exhausted retries" do
          Sentry.configuration.sidekiq.report_after_job_retries = true

          reported_errors = [2, 3, 4].map do |retry_count|
            message = sidekiq_message(failing_job, retry: true, retry_count: retry_count)
            process(message, adapter_skipped: adapter_skipped).grep(Sentry::ErrorEvent).size
          end

          expect(reported_errors).to eq([0, 0, 1])
        end

        it "uses the running retry limit when applying an attempt threshold" do
          reported_errors = [2, 3, 4].map do |retry_count|
            message = sidekiq_message(failing_job, retry: true, retry_count: retry_count, attempt_threshold: 10)
            process(message, adapter_skipped: adapter_skipped).grep(Sentry::ErrorEvent).size
          end

          expect(reported_errors).to eq([0, 0, 1])
        end
      end
    end
  end

  context "when the job is enqueued" do
    let(:enqueued_queue) { Sidekiq::Queue.new("events") }
    let(:user) { { "id" => "42", "segment" => "beta", "ip_address" => "1.2.3.4" } }
    let(:message_specific_data) { %w[messaging.message.id messaging.message.body.size] }

    let(:enqueue_result) { Struct.new(:parent, :publish_spans, :pushed_job) }

    before do
      Sentry.configuration.data_collection.user_info = true
      enqueued_queue.clear
    end

    after { enqueued_queue.clear }

    def enqueue(adapter_skipped:)
      skip_sidekiq_adapter(adapter_skipped)
      enqueued_queue.clear
      transport.events.clear
      Sentry.set_user(user)
      parent = Sentry.start_transaction(name: "enqueuer", op: "test")
      Sentry.get_current_scope.set_span(parent)

      parity_job.perform_later("sku")

      parent.finish
      Sentry.get_current_scope.clear
      parent_event = transport.events.find { |event| event.is_a?(Sentry::TransactionEvent) }
      publish_spans = parent_event.spans.select { |span| span[:op] == "queue.publish" }
      enqueue_result.new(parent, publish_spans, enqueued_queue.first.item)
    end

    def enqueue_and_process(adapter_skipped:)
      enqueued = enqueue(adapter_skipped: adapter_skipped)
      [enqueued, consumer_transaction(enqueued.pushed_job, adapter_skipped: adapter_skipped)]
    end

    it "records the queue.publish span sentry-sidekiq records today when the adapter is not skipped" do
      sidekiq_enqueue = enqueue(adapter_skipped: true)
      active_job_enqueue = enqueue(adapter_skipped: false)
      expect(sidekiq_enqueue.publish_spans.size).to eq(1)
      expect(active_job_enqueue.publish_spans.size).to eq(1)
      sidekiq_span = sidekiq_enqueue.publish_spans.first
      active_job_span = active_job_enqueue.publish_spans.first

      expect(active_job_span.slice(:description, :origin)).to eq(sidekiq_span.slice(:description, :origin))
      expect(active_job_span[:data]).to include(sidekiq_span[:data].except(*message_specific_data))
      expect(active_job_span[:data]["messaging.message.id"]).to eq(active_job_enqueue.pushed_job["jid"])
      expect(active_job_span[:data]["messaging.message.body.size"]).to be_nil.or eq(Sidekiq.dump_json(active_job_enqueue.pushed_job).bytesize)
    end

    it "carries the same trace headers and the whole scope user to the job when the adapter is not skipped" do
      sidekiq_enqueue, sidekiq_transaction = enqueue_and_process(adapter_skipped: true)
      active_job_enqueue, active_job_transaction = enqueue_and_process(adapter_skipped: false)

      expect(active_job_enqueue.pushed_job.slice("trace_propagation_headers", "sentry_user").keys)
        .to eq(sidekiq_enqueue.pushed_job.slice("trace_propagation_headers", "sentry_user").keys)
      expect(active_job_enqueue.pushed_job["sentry_user"]).to eq(user)
      expect(active_job_transaction.user).to eq(sidekiq_transaction.user)
      [[sidekiq_enqueue, sidekiq_transaction], [active_job_enqueue, active_job_transaction]].each do |enqueued, transaction|
        expect(transaction.contexts[:trace]).to include(trace_id: enqueued.parent.trace_id, parent_span_id: enqueued.parent.span_id)
      end
    end

    context "with sidekiq propagate_traces = false" do
      before { Sentry.configuration.sidekiq.propagate_traces = false }

      context "when the job generates outgoing trace headers" do
        let(:parity_job) do
          stub_const("PropagatingParityJob", Class.new(ActiveJob::Base) do
            self.queue_adapter = :sidekiq
            queue_as :events

            def perform(*)
              Sentry.capture_message("outgoing headers", extra: { headers: Sentry.get_trace_propagation_headers })
            end
          end)
        end

        it "uses the new consumer transaction's trace without changing the propagation setting" do
          enqueued = enqueue(adapter_skipped: false)

          expect(enqueued.pushed_job).not_to have_key("trace_propagation_headers")
          expect(enqueued.pushed_job["args"].first.dig("_sentry", "trace_propagation_headers")).to be_nil

          events = process(enqueued.pushed_job, adapter_skipped: false)
          transaction = consumer_transactions(events).first
          event = events.grep(Sentry::ErrorEvent).find { |entry| entry.message == "outgoing headers" }
          headers = event.extra[:headers]
          consumer_trace_id = transaction.contexts.dig(:trace, :trace_id)

          expect(consumer_trace_id).not_to eq(enqueued.parent.trace_id)
          expect(headers["sentry-trace"].split("-").first).to eq(consumer_trace_id)
          expect(headers["baggage"]).to include("sentry-trace_id=#{consumer_trace_id}")
        end
      end

      it "starts a new trace for the job whether the adapter is skipped or not" do
        [true, false].each do |adapter_skipped|
          enqueued, transaction = enqueue_and_process(adapter_skipped: adapter_skipped)

          expect(enqueued.pushed_job).not_to have_key("trace_propagation_headers")
          expect(transaction.contexts.dig(:trace, :trace_id)).not_to eq(enqueued.parent.trace_id)
        end
      end
    end
  end

  context "with the adapter not skipped" do
    it "keeps reporting plain Sidekiq workers through sentry-sidekiq" do
      skip_sidekiq_adapter(false)

      execute_worker(processor, HappyWorker)

      transaction = consumer_transactions(transport.events).first
      expect(transaction.transaction).to eq("Sidekiq/HappyWorker")
      expect(transaction.contexts.dig(:trace, :origin)).to eq("auto.queue.sidekiq")
    end

    it "keeps ActiveJob's own naming for jobs run on other adapters" do
      skip_sidekiq_adapter(false)
      inline_job = stub_const("InlineParityJob", Class.new(ActiveJob::Base) do
        self.queue_adapter = :inline

        def perform; end
      end)

      inline_job.perform_later

      transaction = consumer_transactions(transport.events).first
      expect(transaction.transaction).to eq("InlineParityJob")
      expect(transaction.contexts.dig(:trace, :origin)).to eq("auto.queue.active_job")
    end
  end
end
