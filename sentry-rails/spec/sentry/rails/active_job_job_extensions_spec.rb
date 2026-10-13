# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Sentry + ActiveJob with a registered job extension", type: :job do
  include_context "active_job backend harness", adapter: :test
  include_context "test adapter"

  let(:configure_sentry) { proc { |config| config.traces_sample_rate = 1.0 } }

  def register_extension(&body)
    klass = Class.new(Sentry::JobExtensions::Extension) do
      def handles?(_job)
        true
      end

      class_eval(&body) if body
    end

    Sentry.register_job_extension(klass.new(name: "test_backend"))
  end

  def perform_failing_job
    expect do
      failing_job.perform_later
      drain
    end.to raise_error(RuntimeError, /boom from failing_job spec/)

    error_event
  end

  def error_event
    sentry_events.find { |event| event.is_a?(Sentry::ErrorEvent) }
  end

  def publish_span
    parent = transactions.find { |t| t.contexts.dig(:trace, :op) == "test" }
    parent.spans.find { |span| span[:op] == "queue.publish" }
  end

  def register_enriching_extension
    register_extension do
      def scope_data(job:)
        {
          contexts: { backend: { "jid" => "backend-jid" }, active_job: { job_id: "backend", attempt: 3 } },
          tags: { "backend.queue" => "low", queue: "backend-queue" },
          extra: { backend_payload_size: 12, job_id: "backend" }
        }
      end

      def error_data(job:, exception:)
        {
          contexts: { backend_error: { "retried" => true }, active_job: { job_id: "backend" } },
          tags: { "backend.error" => "yes", job_id: "backend", provider_job_id: "backend" },
          extra: { backend_attempts: 2, active_job: "backend" }
        }
      end

      def messaging_data(job:)
        { system: "backend", message_id: "backend", destination: "backend", receive_latency: 42.0 }
      end
    end
  end

  describe "scope data" do
    before { register_enriching_extension }

    it "adds the extension's contexts, tags and extra to the consumer transaction while keeping ActiveJob's values" do
      successful_job.perform_later
      drain

      transaction = consumer_transaction

      expect(transaction.contexts[:backend]).to eq("jid" => "backend-jid")
      expect(transaction.contexts[:active_job]).to include(job_class: successful_job.name, attempt: 3)
      expect(transaction.contexts[:active_job][:job_id]).not_to eq("backend")
      expect(transaction.tags).to include("backend.queue" => "low", queue: "default")
      expect(transaction.extra).to include(backend_payload_size: 12)
    end

    it "adds the extension's scope data to the error event while keeping ActiveJob's values" do
      event = perform_failing_job

      expect(event.contexts[:backend]).to eq("jid" => "backend-jid")
      expect(event.tags).to include("backend.queue" => "low", queue: "default")
      expect(event.extra).to include(backend_payload_size: 12)
      expect(event.extra[:job_id]).not_to eq("backend")
    end
  end

  describe "error data" do
    before { register_enriching_extension }

    it "adds the extension's error data to the captured event while keeping ActiveJob's values" do
      event = perform_failing_job

      expect(event.contexts[:backend_error]).to eq("retried" => true)
      expect(event.tags).to include("backend.error" => "yes")
      expect(event.extra).to include(backend_attempts: 2, active_job: failing_job.name)
      expect(event.tags[:job_id]).to eq(event.extra[:job_id])
      expect(event.tags[:provider_job_id]).to eq(event.extra[:provider_job_id])
      expect(event.contexts[:active_job][:job_id]).to eq(event.extra[:job_id])
    end
  end

  describe "error data overlapping the job's scope" do
    it "does not let the extension's error data replace tags and extra already on the job's scope" do
      register_extension do
        def scope_data(job:)
          { tags: { "backend.queue" => "low" }, extra: { backend_payload_size: 12 } }
        end

        def error_data(job:, exception:)
          { tags: { "backend.queue" => "high", queue: "backend-queue" }, extra: { backend_payload_size: 99 } }
        end
      end

      event = perform_failing_job

      expect(event.tags).to include("backend.queue" => "low", queue: "default")
      expect(event.extra).to include(backend_payload_size: 12)
    end
  end

  describe "error data with Rails execution context", skip: RAILS_VERSION < 7.0 do
    context "when queue data collection is enabled" do
      let(:configure_sentry) do
        proc do |config|
          config.traces_sample_rate = 1.0
          config.data_collection.queues = true
        end
      end

      let(:failing_job) do
        job_fixture do
          def perform
            Rails.error.set_context(debug_key: "from_job")
            raise "boom from failing_job spec"
          end
        end
      end

      it "keeps ActiveJob's execution context alongside the extension's contexts" do
        register_extension do
          def error_data(job:, exception:)
            { contexts: { "rails.error" => { debug_key: "backend" }, backend_error: { "retried" => true } } }
          end
        end

        event = perform_failing_job

        expect(event.contexts["rails.error"]).to include(debug_key: "from_job")
        expect(event.contexts[:backend_error]).to eq("retried" => true)
      end
    end
  end

  describe "messaging data" do
    before { register_enriching_extension }

    it "adds the extension's messaging data to the producer span only where ActiveJob sets none" do
      within_parent_transaction do
        successful_job.set(queue: "events").perform_later
      end

      expect(publish_span[:data]).to include(
        "messaging.system" => successful_job.queue_adapter_name,
        "messaging.destination.name" => "events",
        "messaging.message.receive.latency" => 42.0
      )
      expect(publish_span[:data]["messaging.message.id"]).not_to eq("backend")
    end

    it "reports the extension's messaging data on the consumer transaction in place of ActiveJob's" do
      successful_job.set(queue: "events").perform_later
      drain

      expect(consumer_transaction.contexts.dig(:trace, :data)).to include(
        "messaging.system" => "backend",
        "messaging.message.id" => "backend",
        "messaging.destination.name" => "backend",
        "messaging.message.receive.latency" => 42.0
      )
    end
  end

  describe "user" do
    let(:configure_sentry) do
      proc do |config|
        config.traces_sample_rate = 1.0
        config.send_default_pii = true
      end
    end

    it "replaces the user the job carries with the user the extension supplies" do
      register_extension do
        def scope_data(job:)
          { user: { "id" => "backend-user", "segment" => "vip" } }
        end
      end
      Sentry.set_user(id: "web-user")

      successful_job.perform_later
      Sentry.set_user({})

      expect(last_enqueued_payload.dig("_sentry", "user")).to eq("id" => "web-user")

      drain

      expect(consumer_transaction.user).to eq("id" => "backend-user", "segment" => "vip")
    end
  end

  describe "retry info" do
    def register_retrying_extension(count:, will_retry:)
      register_extension do
        define_method(:retry_info) { |job:| { count: count, will_retry: will_retry } }
      end
    end

    it "reports the extension's retry count on the producer span and the consumer transaction" do
      register_retrying_extension(count: 4, will_retry: false)

      within_parent_transaction { successful_job.perform_later }
      drain

      expect(publish_span[:data]).to include("messaging.message.retry.count" => 4)
      expect(consumer_transaction.contexts.dig(:trace, :data)).to include("messaging.message.retry.count" => 4)
    end

    it "does not capture the job's exception but still fails the transaction when the backend will retry" do
      register_retrying_extension(count: 1, will_retry: true)

      expect do
        failing_job.perform_later
        drain
      end.to raise_error(RuntimeError, /boom from failing_job spec/)

      expect(error_event).to be_nil
      expect(consumer_transaction.contexts.dig(:trace, :status)).to eq("internal_error")
    end

    it "captures the job's exception when the backend will not retry" do
      register_retrying_extension(count: 5, will_retry: false)

      expect(perform_failing_job).not_to be_nil
    end
  end

  describe "exception reporting" do
    def register_deciding_extension(report:, will_retry:)
      register_extension do
        define_method(:retry_info) { |job:| { count: 1, will_retry: will_retry } }
        define_method(:report_exception?) { |job:, exception:| report }
      end
    end

    it "captures the job's exception when the extension reports it, even though the backend will retry" do
      register_deciding_extension(report: true, will_retry: true)

      expect(perform_failing_job).not_to be_nil
    end

    it "does not capture the job's exception when the extension declines it, but still fails the transaction" do
      register_deciding_extension(report: false, will_retry: false)

      expect(perform_failing_job).to be_nil
      expect(consumer_transaction.contexts.dig(:trace, :status)).to eq("internal_error")
    end
  end

  describe "retried exception reporting" do
    let(:retrying_job) do
      job_fixture do
        retry_on StandardError, attempts: 2, wait: 0

        def perform
          raise "boom from retrying_job spec" if executions == 1
        end
      end
    end

    def register_retry_deciding_extension(report)
      register_extension do
        define_method(:report_retried_exception?) { |job:, exception:| report }
      end
    end

    def perform_retrying_job
      retrying_job.perform_later
      drain
      error_event
    end

    it "does not capture an exception ActiveJob retries when the extension declines it, even with active_job_report_on_retry_error" do
      Sentry.configuration.rails.active_job_report_on_retry_error = true
      register_retry_deciding_extension(false)

      expect(perform_retrying_job).to be_nil
    end

    it "captures an exception ActiveJob retries when the extension reports it, even without active_job_report_on_retry_error" do
      register_retry_deciding_extension(true)

      expect(perform_retrying_job&.exception&.values&.first&.value).to include("boom from retrying_job spec")
    end
  end

  describe "trace headers" do
    let(:foreign_trace_id) { "a" * 32 }
    let(:foreign_trace_headers) { { "sentry-trace" => "#{foreign_trace_id}-#{"b" * 16}-1" } }

    def register_extension_extracting(headers)
      register_extension do
        define_method(:extract_trace_headers) { |job:, payload:| headers }
      end
    end

    it "lets the extension carry the trace headers in the serialized payload alongside _sentry" do
      register_extension do
        def inject_trace_headers(job:, payload:, headers:)
          payload.merge("backend_trace" => headers["sentry-trace"])
        end
      end

      within_parent_transaction { successful_job.perform_later }

      payload = last_enqueued_payload
      expect(payload["backend_trace"]).not_to be_nil
      expect(payload["backend_trace"]).to eq(payload["_sentry"]["trace_propagation_headers"]["sentry-trace"])
    end

    context "when the job carries no _sentry trace headers" do
      let(:configure_sentry) do
        proc do |config|
          config.traces_sample_rate = 1.0
          config.rails.active_job_propagate_traces = false
        end
      end

      it "continues the trace the extension extracts" do
        register_extension_extracting(foreign_trace_headers)

        successful_job.perform_later
        drain

        expect(consumer_transaction.contexts.dig(:trace, :trace_id)).to eq(foreign_trace_id)
      end
    end

    it "continues the _sentry trace even when the extension extracts different headers" do
      register_extension_extracting(foreign_trace_headers)
      parent_trace_id = nil

      within_parent_transaction do |parent|
        parent_trace_id = parent.trace_id
        successful_job.perform_later
      end
      drain

      expect(consumer_transaction.contexts.dig(:trace, :trace_id)).to eq(parent_trace_id)
    end
  end

  describe "naming" do
    let(:backend_integration) do
      Module.new do
        extend Sentry::Integrable

        def self.integration_name
          "backend"
        end
      end
    end

    def mechanism_type(event)
      event.exception.values.first.mechanism.type
    end

    before do
      integration = backend_integration
      register_extension do
        define_method(:transaction_name) { |job:| "Backend/#{job.class.name}" }
        define_method(:span_origin) { |job:| "auto.queue.backend" }
        define_method(:publish_description) { |job:| "Backend/#{job.class.name}" }
        define_method(:integration) { |job:| integration }
      end
    end

    it "names the consumer transaction and sets its origin as the extension supplies" do
      successful_job.perform_later
      drain

      transaction = consumer_transaction

      expect(transaction.transaction).to eq("Backend/#{successful_job.name}")
      expect(transaction.transaction_info).to eq(source: :task)
      expect(transaction.contexts.dig(:trace, :origin)).to eq("auto.queue.backend")
    end

    it "describes the producer span and sets its origin as the extension supplies" do
      within_parent_transaction { successful_job.perform_later }

      expect(publish_span[:description]).to eq("Backend/#{successful_job.name}")
      expect(publish_span[:origin]).to eq("auto.queue.backend")
    end

    it "captures the job's exception under the extension's integration and transaction name" do
      event = perform_failing_job

      expect(mechanism_type(event)).to eq("backend")
      expect(event.transaction).to eq("Backend/#{failing_job.name}")
    end
  end

  describe "enqueue instrumentation" do
    let(:configure_sentry) do
      proc do |config|
        config.traces_sample_rate = 1.0
        config.data_collection.user_info = true
      end
    end

    it "leaves the producer span, trace headers and user to an extension that instruments enqueueing the job" do
      register_extension do
        def instruments_enqueue?(job:)
          true
        end
      end
      Sentry.set_user(id: "42")

      within_parent_transaction { successful_job.perform_later }

      expect(publish_span).to be_nil
      expect(last_enqueued_payload).not_to have_key("_sentry")
    end
  end

  describe "when the extension adds nothing" do
    let(:extension_data_keys) { [:backend, "backend.queue", :backend_payload_size, :backend_error, "backend.error", :backend_attempts] }

    def expect_no_extension_data(event)
      expect(event.contexts.keys & extension_data_keys).to be_empty
      expect(event.tags.keys & extension_data_keys).to be_empty
      expect(event.extra.keys & extension_data_keys).to be_empty
    end

    it "sends nothing from an extension that does not handle the job" do
      register_enriching_extension.define_singleton_method(:handles?) { |_job| false }

      within_parent_transaction { failing_job.perform_later }
      expect { drain }.to raise_error(RuntimeError, /boom from failing_job spec/)

      expect_no_extension_data(error_event)
      expect_no_extension_data(consumer_transaction)
      expect(publish_span[:data]).not_to have_key("messaging.message.receive.latency")
    end

    it "never consults the registry for jobs on a skipped adapter" do
      consulted = []
      Sentry.register_job_extension(
        Class.new(Sentry::JobExtensions::Extension) do
          define_method(:handles?) do |job|
            consulted << job
            true
          end
        end.new(name: "observer")
      )
      Sentry.configuration.rails.skippable_job_adapters = [failing_job.queue_adapter.class.to_s]

      expect do
        failing_job.perform_later
        drain
      end.to raise_error(RuntimeError, /boom from failing_job spec/)

      expect(consulted).to be_empty
    end

    {
      "raises" => proc { raise "extension failure" },
      "returns malformed data" => proc { :malformed }
    }.each do |behavior, hook_body|
      context "when every hook #{behavior}" do
        before do
          register_extension do
            %i[scope_data error_data messaging_data transaction_name span_origin publish_description integration instruments_enqueue?].each do |hook|
              define_method(hook) { |**_args| instance_exec(&hook_body) }
            end
          end
        end

        it "still performs the job and finishes its transaction" do
          within_parent_transaction { successful_job.perform_later }
          drain

          expect(consumer_transaction.contexts.dig(:trace, :status)).to eq("ok")
          expect(consumer_transaction.transaction).to eq(successful_job.name)
          expect(consumer_transaction.contexts.dig(:trace, :origin)).to eq("auto.queue.active_job")
          expect(publish_span[:data]).not_to have_key("messaging.message.receive.latency")
          expect(publish_span[:description]).to eq(successful_job.name)
          expect(publish_span[:origin]).to eq("auto.queue.active_job")
        end

        it "still captures the job's exception with ActiveJob's data" do
          event = perform_failing_job

          expect(event.extra).to include(active_job: failing_job.name)
          expect(event.tags[:job_id]).to eq(event.extra[:job_id])
          expect(event.transaction).to eq(failing_job.name)
          expect(event.exception.values.first.mechanism.type).to eq("rails")
        end
      end
    end
  end
end
