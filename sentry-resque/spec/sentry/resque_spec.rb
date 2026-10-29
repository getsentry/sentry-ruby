# frozen_string_literal: true

require "spec_helper"

def process_job(worker)
  worker.work_one_job(worker.reserve)
end

RSpec.describe Sentry::Resque do
  before do
    perform_basic_setup
  end

  class FailedJob
    def self.perform
      1/0
    end
  end

  class FailedRetriableJob
    extend Resque::Plugins::Retry

    @queue = :default
    @retry_limit = 3

    def self.perform
      1/0
    end
  end

  class FailedZeroRetriesJob < FailedRetriableJob
    @retry_limit = 0
  end

  class TaggedFailedJob
    def self.perform
      Sentry.set_tags(number: 1)
      1/0
    end
  end

  class MessageJob
    def self.perform(msg)
      Sentry.capture_message(msg)
    end
  end

  class TaggedMessageJob
    def self.perform(msg)
      Sentry.set_tags(number: 1)
      Sentry.capture_message(msg)
    end
  end

  let(:transport) do
    Sentry.get_current_client.transport
  end

  let(:worker) do
    Resque::Worker.new(:default)
  end

  it "sets correct extra/tags context for each job" do
    Resque::Job.create(:default, MessageJob, "report")

    process_job(worker)

    expect(transport.events.count).to eq(1)
    event = transport.events.last.to_h
    expect(event[:message]).to eq("report")
    expect(event[:tags]).to eq({ "resque.queue" => "default" })
    expect(event[:contexts][:"Resque"]).to include({ job_class: "MessageJob", arguments: ["report"], queue: "default" })
  end

  it "doesn't leak scope data outside of the job" do
    Resque::Job.create(:default, MessageJob, "report")

    process_job(worker)

    expect(transport.events.count).to eq(1)
    expect(Sentry.get_current_scope.extra).to eq({})
    expect(Sentry.get_current_scope.tags).to eq({})
  end

  it "doesn't share scope data between jobs" do
    Resque::Job.create(:default, TaggedMessageJob, "tagged report")

    process_job(worker)

    expect(transport.events.count).to eq(1)
    event = transport.events.last.to_h
    expect(event[:message]).to eq("tagged report")
    expect(event[:tags]).to include({ number: 1 })

    Resque::Job.create(:default, MessageJob, "report")

    process_job(worker)

    expect(transport.events.count).to eq(2)
    event = transport.events.last.to_h
    expect(event[:tags]).to eq({ "resque.queue" => "default" })
  end

  context "when a job failed" do
    it "reports exception" do
      expect do
        Resque::Job.create(:default, FailedJob)
        process_job(worker)
      end.to change { Resque::Stat.get("failed") }.by(1)

      expect(transport.events.count).to eq(1)
      event = transport.events.last.to_h

      expect(event[:sdk]).to eq({ name: "sentry.ruby.resque", version: described_class::VERSION })
      expect(event.dig(:exception, :values, 0, :type)).to eq("ZeroDivisionError")
      expect(event[:tags]).to eq({ "resque.queue" => "default" })
    end

    it "doesn't leak scope data" do
      expect do
        Resque::Job.create(:default, TaggedFailedJob)
        process_job(worker)
      end.to change { Resque::Stat.get("failed") }.by(1)

      expect(transport.events.count).to eq(1)
      event = transport.events.last.to_h

      expect(event[:tags]).to eq({ "resque.queue" => "default", number: 1 })
      expect(Sentry.get_current_scope.extra).to eq({})
      expect(Sentry.get_current_scope.tags).to eq({})

      expect do
        Resque::Job.create(:default, FailedJob)
        process_job(worker)
      end.to change { Resque::Stat.get("failed") }.by(1)

      expect(transport.events.count).to eq(2)
      event = transport.events.last.to_h
      expect(event[:tags]).to eq({ "resque.queue" => "default" })
      expect(Sentry.get_current_scope.extra).to eq({})
      expect(Sentry.get_current_scope.tags).to eq({})
    end
  end

  context "with ResqueRetry" do
    context "when report_after_job_retries is true" do
      before do
        Sentry.configuration.resque.report_after_job_retries = true
      end

      it "reports exception only on the last run" do
        expect do
          Resque::Job.create(:default, FailedRetriableJob)
          process_job(worker)
        end.to change { Resque::Stat.get("failed") }.by(1)
           .and change { transport.events.count }.by(0)

        expect do
          3.times do
            process_job(worker)
          end
        end.to change { transport.events.count }.by(1)

        event = transport.events.last.to_h

        expect(event[:sdk]).to eq({ name: "sentry.ruby.resque", version: described_class::VERSION })
        expect(event.dig(:exception, :values, 0, :type)).to eq("ZeroDivisionError")
        expect(event[:tags]).to eq({ "resque.queue" => "default" })
      end

      it "reports exception on first run when retry_count is 0" do
        expect do
          Resque::Job.create(:default, FailedZeroRetriesJob)
          process_job(worker)
        end.to change { Resque::Stat.get("failed") }.by(1)
           .and change { transport.events.count }.by(1)

        event = transport.events.last.to_h

        expect(event[:sdk]).to eq({ name: "sentry.ruby.resque", version: described_class::VERSION })
        expect(event.dig(:exception, :values, 0, :type)).to eq("ZeroDivisionError")
        expect(event[:tags]).to eq({ "resque.queue" => "default" })
      end
    end

    context "when report_after_job_retries is false" do
      before do
        Sentry.configuration.resque.report_after_job_retries = false
      end

      it "reports exeception all the runs" do
        expect do
          Resque::Job.create(:default, FailedRetriableJob)
          process_job(worker)
        end.to change { Resque::Stat.get("failed") }.by(1)
           .and change { transport.events.count }.by(1)

        expect do
          3.times do
            process_job(worker)
          end
        end.to change { transport.events.count }.by(3)

        event = transport.events.last.to_h

        expect(event[:sdk]).to eq({ name: "sentry.ruby.resque", version: described_class::VERSION })
        expect(event.dig(:exception, :values, 0, :type)).to eq("ZeroDivisionError")
        expect(event[:tags]).to eq({ "resque.queue" => "default" })
      end
    end

    context "with Resque.inline = true" do
      around do |example|
        Resque.inline = true
        example.run
        Resque.inline = false
      end

      it 'reports the class properly' do
        expect do
          Resque::Job.create(:default, FailedRetriableJob)
          process_job(worker)
        end.not_to raise_error(TypeError)

        event = transport.events.last.to_h
        expect(event.dig(:exception, :values, 0, :type)).to eq("ZeroDivisionError")
      end
    end
  end

  rails_gems = begin
    require "rails"
    require "active_job"
    require "sentry-rails"
    true
  rescue LoadError
    false
  end

  context "with ActiveJob" do
    class AJMessageJob < ActiveJob::Base
      self.queue_adapter = :resque

      def perform(msg)
        Sentry.set_tags(number: 1)
        Sentry.capture_message(msg)
      end
    end

    class AJFailedJob < ActiveJob::Base
      self.queue_adapter = :resque

      def perform
        Sentry.set_tags(number: 2)
        1 / 0
      end
    end

    before do
      ActiveJob::Base.logger = nil

      # because we don't create a full Rails app here, we need to apply sentry-rails' ActiveJob extension manually
      require "sentry/rails/active_job"
      ActiveJob::Base.send(:prepend, Sentry::Rails::ActiveJobExtensions)

      if Sentry.configuration.rails.skippable_job_adapters.empty?
        Sentry.configuration.rails.skippable_job_adapters << "ActiveJob::QueueAdapters::ResqueAdapter"
      end
    end

    context "when the job succeeded" do
      before do
        AJMessageJob.perform_later("report from ActiveJob")

        process_job(worker)
      end

      it "doesn't leak scope data" do
        expect(transport.events.count).to eq(1)

        expect(Sentry.get_current_scope.tags).to eq({})
      end

      it "injects ActiveJob information to the event" do
        expect(transport.events.count).to eq(1)

        event = transport.events.last.to_h
        expect(event[:message]).to eq("report from ActiveJob")
        expect(event[:tags]).to match({ "resque.queue" => "default", number: 1 })
        expect(event[:contexts][:"Active-Job"][:job_class]).to eq("AJMessageJob")
      end
    end

    context "when the job failed" do
      before do
        AJFailedJob.perform_later

        expect do
          process_job(worker)
        end.to change { Resque::Stat.get("failed") }.by(1)
      end

      it "doesn't duplicate error reporting" do
        expect(transport.events.count).to eq(1)

        expect(Sentry.get_current_scope.tags).to eq({})
      end

      it "injects ActiveJob information to the event" do
        expect(transport.events.count).to eq(1)

        event = transport.events.last.to_h
        expect(event.dig(:exception, :values, 0, :type)).to eq("ZeroDivisionError")
        expect(event[:tags]).to match({ "resque.queue" => "default", number: 2 })
        expect(event[:contexts][:"Active-Job"][:job_class]).to eq("AJFailedJob")
      end
    end

    context "with tracing enabled" do
      let(:transactions) { transport.events.select { |event| event.is_a?(Sentry::TransactionEvent) } }
      let(:errors) { transport.events.reject { |event| event.is_a?(Sentry::TransactionEvent) } }

      {
        "the Resque adapter is skippable" => [:resque, ["ActiveJob::QueueAdapters::ResqueAdapter"]],
        "opted in to the sentry-rails ActiveJob integration" => [:rails, []]
      }.each do |mode, (active_job_integration, skippable_job_adapters)|
        it "should record a plain Resque job in a queue.resque transaction when #{mode}" do
          perform_basic_setup do |config|
            config.traces_sample_rate = 1.0
            config.resque.active_job_integration = active_job_integration
            config.rails.skippable_job_adapters = skippable_job_adapters
          end
          Resque::Job.create(:default, FailedJob)

          process_job(worker)

          expect(transactions.count).to eq(1)
          expect(transactions.first.to_h.dig(:contexts, :trace)).to include(op: "queue.resque", origin: "auto.queue.resque")
          expect(errors.count).to eq(1)
          expect(errors.first.to_h.dig(:contexts, :Resque)).to include(job_class: "FailedJob", queue: "default", worker: worker.to_s)
        end
      end

      it "should keep the Resque transaction and error event of an ActiveJob job when the adapter is skippable" do
        perform_basic_setup do |config|
          config.traces_sample_rate = 1.0
          config.rails.skippable_job_adapters = ["ActiveJob::QueueAdapters::ResqueAdapter"]
        end
        AJFailedJob.perform_later

        process_job(worker)

        expect(transactions.count).to eq(1)
        transaction = transactions.first.to_h
        expect(transaction[:transaction]).to eq("AJFailedJob")
        expect(transaction.dig(:contexts, :trace)).to include(op: "queue.resque", origin: "auto.queue.resque", status: "internal_error")
        expect(errors.count).to eq(1)
        error = errors.first.to_h
        expect(error[:sdk][:name]).to eq("sentry.ruby.resque")
        expect(error[:tags]).to eq("resque.queue" => "default", number: 2)
        expect(error[:contexts][:"Active-Job"]).to include(job_class: "AJFailedJob", queue: "default", worker: worker.to_s)
      end

      {
        "by default when the adapter is not skippable" => [nil, []],
        "when set to :rails but the adapter is skippable" => [:rails, ["ActiveJob::QueueAdapters::ResqueAdapter"]]
      }.each do |mode, (active_job_integration, skippable_job_adapters)|
        it "should keep the Resque transaction of an ActiveJob job #{mode}" do
          perform_basic_setup do |config|
            config.traces_sample_rate = 1.0
            config.resque.active_job_integration = active_job_integration if active_job_integration
            config.rails.skippable_job_adapters = skippable_job_adapters
          end
          AJFailedJob.perform_later

          process_job(worker)

          resque_transaction = transactions.find { |transaction| transaction.contexts.dig(:trace, :op) == "queue.resque" }
          expect(resque_transaction.to_h.dig(:contexts, :trace)).to include(origin: "auto.queue.resque", status: "internal_error")
          expect(errors.count).to eq(1)
        end
      end
    end

    context "when opted in to the sentry-rails ActiveJob integration" do
      before do
        perform_basic_setup do |config|
          config.traces_sample_rate = 1.0
          config.resque.active_job_integration = :rails
          config.rails.skippable_job_adapters = []
        end
      end

      let(:transactions) { transport.events.select { |event| event.is_a?(Sentry::TransactionEvent) } }
      let(:errors) { transport.events.reject { |event| event.is_a?(Sentry::TransactionEvent) } }

      it "should report a failed job once in a single queue.process transaction" do
        AJFailedJob.perform_later

        expect do
          process_job(worker)
        end.to change { Resque::Stat.get("failed") }.by(1)

        expect(errors.count).to eq(1)
        expect(errors.first.to_h[:sdk][:name]).to eq("sentry.ruby.resque")
        expect(transactions.count).to eq(1)
        expect(transactions.first.to_h.dig(:contexts, :trace)).to include(op: "queue.process", origin: "auto.queue.resque")
      end

      it "should describe the Resque job that performed the ActiveJob job" do
        AJFailedJob.perform_later
        raw_resque_message = Resque.redis.lindex("queue:default", 0)

        process_job(worker)

        expect(errors.first.to_h.dig(:contexts, :"Active-Job")).to include(
          job_class: "AJFailedJob",
          queue: "default",
          worker: worker.to_s
        )
        expect(transactions.first.to_h.dig(:contexts, :trace, :data)).to include(
          "messaging.message.body.size" => raw_resque_message.bytesize
        )
      end

      it "should report a job whose class can no longer be loaded" do
        AJMessageJob.perform_later("report from ActiveJob")
        payload = Resque.decode(Resque.redis.lpop("queue:default"))
        payload["args"].first["job_class"] = "RemovedJob"
        Resque.redis.rpush("queue:default", Resque.encode(payload))

        expect do
          process_job(worker)
        end.to change { Resque::Stat.get("failed") }.by(1)

        expect(errors.count).to eq(1)
        error = errors.first.to_h
        expect(error[:sdk][:name]).to eq("sentry.ruby.resque")
        expect(error.dig(:exception, :values, 0, :value)).to include("RemovedJob")
        expect(error[:tags]).to include("resque.queue" => "default")
        expect(error[:contexts][:"Active-Job"]).to include(job_class: "RemovedJob", queue: "default", worker: worker.to_s)
      end

      it "should leave the Resque payload of a failed job unchanged" do
        AJFailedJob.perform_later
        enqueued_payload = Resque.decode(Resque.redis.lindex("queue:default", 0))

        process_job(worker)

        expect(Resque::Failure.all(Resque::Failure.count - 1)["payload"]).to eq(enqueued_payload)
      end

      it "should report a failed job on its first run when report_after_job_retries is true" do
        Sentry.configuration.resque.report_after_job_retries = true
        AJFailedJob.perform_later

        process_job(worker)

        expect(errors.count).to eq(1)
      end

      context "when ActiveJob retries the job" do
        class AJRetriedJob < ActiveJob::Base
          self.queue_adapter = :resque
          retry_on ZeroDivisionError, attempts: 2, wait: ->(_executions) { nil }

          def perform
            1 / 0
          end
        end

        around do |example|
          Sentry::Rails::ActiveJobExtensions::SentryReporter.register_event_handlers
          example.run
        ensure
          Sentry::Rails::ActiveJobExtensions::SentryReporter.detach_event_handlers
        end

        it "should not report the retried exception even when active_job_report_on_retry_error is true" do
          Sentry.configuration.rails.active_job_report_on_retry_error = true
          AJRetriedJob.perform_later

          process_job(worker)

          expect(Resque.size("default")).to eq(1)
          expect(errors).to be_empty
        end
      end
    end
  end if rails_gems
end


RSpec.describe Sentry::Resque, "not initialized" do
  class FailedJob
    def self.perform
      1/0
    end
  end

  let(:worker) do
    Resque::Worker.new(:default)
  end

  it "doesn't swallow jobs" do
    expect do
      Resque::Job.create(:default, FailedJob)
      process_job(worker)
    end.to change { Resque::Stat.get("failed") }.by(1)
  end
end
