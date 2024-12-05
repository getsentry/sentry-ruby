# frozen_string_literal: true

require "spec_helper"
require 'sidekiq/manager'
require 'sidekiq/api'

RSpec.describe Sentry::Sidekiq do
  before do
    perform_basic_setup
  end

  let(:queue) do
    Sidekiq::Queue.new("default")
  end

  let(:retry_set) do
    Sidekiq::RetrySet.new
  end

  before do
    retry_set.clear
    queue.clear
  end

  after do
    # those test jobs will go into the real Redis and be visiable to other sidekiq processes
    # this can affect local testing and development, so we should clear them after each test
    retry_set.clear
    queue.clear
  end

  let(:processor) do
    new_processor
  end

  let(:transport) do
    Sentry.get_current_client.transport
  end

  it "registers error handlers and middlewares" do
    if WITH_SIDEKIQ_7
      config = Sidekiq.instance_variable_get(:@config)

      expect(config.error_handlers).to include(described_class::ErrorHandler)
      expect(config.server_middleware.entries.map(&:klass)).to include(described_class::SentryContextServerMiddleware)
      expect(config.client_middleware.entries.map(&:klass)).to include(described_class::SentryContextClientMiddleware)
    else
      expect(Sidekiq.error_handlers).to include(described_class::ErrorHandler)
      expect(Sidekiq.server_middleware.entries.first.klass).to eq(described_class::SentryContextServerMiddleware)
      expect(Sidekiq.client_middleware.entries.first.klass).to eq(described_class::SentryContextClientMiddleware)
    end
  end

  it "captures exception raised in the worker" do
    expect { execute_worker(processor, SadWorker) }.to change { transport.events.size }.by(1)

    event = transport.events.last.to_hash
    expect(event[:sdk]).to eq({ name: "sentry.ruby.sidekiq", version: described_class::VERSION })
    expect(event[:exception][:values][0][:type]).to eq("RuntimeError")
    expect(event[:exception][:values][0][:value]).to match("I'm sad!")
  end

  it "doesn't store the private `_config` context", skip: !WITH_SIDEKIQ_7 do
    expect { execute_worker(processor, SadWorker) }.to change { transport.events.size }.by(1)

    event = transport.events.last.to_hash
    expect(event[:contexts][:sidekiq].keys.map(&:to_s)).not_to include("_config")
  end

  describe "context cleanup" do
    it "cleans up context from processed jobs" do
      execute_worker(processor, HappyWorker)
      execute_worker(processor, SadWorker)

      expect(transport.events.count).to eq(1)
      event = transport.events.last.to_json_compatible

      expect(event["tags"]).to eq("queue" => "default", "jid" => "123123", "mood" => "sad")
      expect(event["transaction"]).to eq("Sidekiq/SadWorker")
      expect(event["breadcrumbs"]["values"][0]["message"]).to eq("I'm sad!")
      expect(Sentry.get_current_scope.tags).to be_empty
    end

    it "cleans up context from failed jobs" do
      execute_worker(processor, SadWorker)
      execute_worker(processor, VerySadWorker)

      expect(transport.events.count).to eq(2)
      event = transport.events.last.to_json_compatible

      expect(event["tags"]).to eq("queue" => "default", "jid" => "123123", "mood" => "very sad")
      expect(event["breadcrumbs"]["values"][0]["message"]).to eq("I'm very sad!")
      expect(Sentry.get_current_scope.tags).to be_empty
    end
  end

  it "has some context when capturing, even if no exception raised" do
    execute_worker(processor, ReportingWorker)

    event = transport.events.last.to_json_compatible

    expect(event["message"]).to eq "I have something to say!"
    expect(event["contexts"]["sidekiq"]).to include("args" => [], "class" => "ReportingWorker", "jid" => "123123", "queue" => "default")
  end

  it "adds the failed job to the retry queue" do
    execute_worker(processor, SadWorker)

    expect(retry_set.count).to eq(1)
  end

  context "with config.report_after_job_retries = true" do
    before do
      Sentry.configuration.sidekiq.report_after_job_retries = true
    end

    def retry_last_failed_job
      retry_set.first.add_to_queue
      job = queue.first
      work = Sidekiq::BasicFetch::UnitOfWork.new('queue:default', job.value)
      process_work(processor, work)
    end

    context "when retry: is specified" do
      it "doesn't report the error until retries are exhuasted" do
        worker = Class.new(SadWorker)
        worker.sidekiq_options retry: 5
        execute_worker(processor, worker)
        expect(transport.events.count).to eq(0)
        expect(retry_set.count).to eq(1)

        4.times do |i|
          retry_last_failed_job
          expect(transport.events.count).to eq(0)
        end

        retry_last_failed_job
        expect(transport.events.count).to eq(1)
      end
    end

    context "when the job has 0 retries" do
      it "reports on the first failure" do
        worker = Class.new(SadWorker)
        worker.sidekiq_options retry: 0

        execute_worker(processor, worker)

        expect(transport.events.count).to eq(1)
      end
    end

    context "when the job has retry: false" do
      it "reports on the first failure" do
        worker = Class.new(SadWorker)
        worker.sidekiq_options retry: false

        execute_worker(processor, worker)

        expect(transport.events.count).to eq(1)
      end
    end

    context "when retry is not specified on the worker" do
      before do
        # this is required for Sidekiq to assign default options to the worker
        SadWorker.sidekiq_options
      end

      it "reports on the 25th retry" do
        execute_worker(processor, SadWorker)
        expect(transport.events.count).to eq(0)
        expect(retry_set.count).to eq(1)

        24.times do |i|
          retry_last_failed_job
          expect(transport.events.count).to eq(0)
        end

        retry_last_failed_job
        expect(transport.events.count).to eq(1)
      end

      context "when Sidekiq.options[:max_retries] is set" do
        it "respects the set limit" do
          if WITH_SIDEKIQ_7
            Sidekiq.default_configuration[:max_retries] = 5
          else
            Sidekiq.options[:max_retries] = 5
          end

          execute_worker(processor, SadWorker)
          expect(transport.events.count).to eq(0)
          expect(retry_set.count).to eq(1)

          4.times do |i|
            retry_last_failed_job
            expect(transport.events.count).to eq(0)
          end

          retry_last_failed_job
          expect(transport.events.count).to eq(1)
        end
      end
    end
  end

  context "when tracing is enabled" do
    before do
      perform_basic_setup do |config|
        config.traces_sample_rate = 1.0
      end
    end

    it "records transaction" do
      execute_worker(processor, HappyWorker)

      expect(transport.events.count).to eq(1)
      transaction = transport.events.first

      expect(transaction.transaction).to eq("Sidekiq/HappyWorker")
      expect(transaction.transaction_info).to eq({ source: :task })
      expect(transaction.contexts.dig(:trace, :trace_id)).to be_a(String)
      expect(transaction.contexts.dig(:trace, :span_id)).to be_a(String)
      expect(transaction.contexts.dig(:trace, :status)).to eq("ok")
      expect(transaction.contexts.dig(:trace, :op)).to eq("queue.process")
    end

    it "records transaction with exception" do
      execute_worker(processor, SadWorker)

      expect(transport.events.count).to eq(2)
      transaction = transport.events.first

      expect(transaction.transaction).to eq("Sidekiq/SadWorker")
      expect(transaction.transaction_info).to eq({ source: :task })
      expect(transaction.contexts.dig(:trace, :trace_id)).to be_a(String)
      expect(transaction.contexts.dig(:trace, :span_id)).to be_a(String)
      expect(transaction.contexts.dig(:trace, :status)).to eq("internal_error")

      event = transport.events.last
      expect(event.contexts.dig(:trace, :trace_id)).to eq(transaction.contexts.dig(:trace, :trace_id))
    end

    context "with instrumenter :otel" do
      before do
        perform_basic_setup do |config|
          config.traces_sample_rate = 1.0
          config.instrumenter = :otel
        end
      end

      it "does not record transaction" do
        execute_worker(processor, SadWorker)
        expect(transport.events.count).to eq(1)
        event = transport.events.first
        expect(event).to be_a(Sentry::ErrorEvent)
      end
    end
  end

  context "cron monitoring" do
    it "records check ins" do
      execute_worker(processor, HappyWorkerWithCron)

      expect(transport.events.size).to eq(2)

      first = transport.events[0]
      check_in_id = first.check_in_id
      expect(first).to be_a(Sentry::CheckInEvent)
      expect(first.to_hash).to include(
        type: 'check_in',
        check_in_id: check_in_id,
        monitor_slug: "happyworkerwithcron",
        status: :in_progress
      )

      second = transport.events[1]
      expect(second).to be_a(Sentry::CheckInEvent)
      expect(second.to_hash).to include(
        :duration,
        type: 'check_in',
        check_in_id: check_in_id,
        monitor_slug: "happyworkerwithcron",
        status: :ok
      )
    end

    it "records check ins with error" do
      execute_worker(processor, SadWorkerWithCron)
      expect(transport.events.size).to eq(3)

      first = transport.events[0]
      check_in_id = first.check_in_id
      expect(first).to be_a(Sentry::CheckInEvent)
      expect(first.to_hash).to include(
        type: 'check_in',
        check_in_id: check_in_id,
        monitor_slug: "failed_job",
        status: :in_progress,
        monitor_config: { schedule: { type: :crontab, value: "5 * * * *" } }
      )

      second = transport.events[1]
      expect(second).to be_a(Sentry::CheckInEvent)
      expect(second.to_hash).to include(
        :duration,
        type: 'check_in',
        check_in_id: check_in_id,
        monitor_slug: "failed_job",
        status: :error,
        monitor_config: { schedule: { type: :crontab, value: "5 * * * *" } }
      )
    end
  end

  if RUBY_VERSION >= "3.2.1"
    context "when profiling is enabled with Vernier" do
      before do
        perform_basic_setup do |config|
          config.traces_sample_rate = 1.0
          config.profiles_sample_rate = 1.0
          config.profiler_class = Sentry::Vernier::Profiler
          config.release = "test-release"
        end
      end

      it "captures meaningful profile data from worker with workload" do
        execute_worker(processor, WorkloadWorker)

        expect(transport.events.count).to eq(1)
        event = transport.events.first

        expect(event).to be_a(Sentry::TransactionEvent)
        profile = event.profile

        expect(profile).not_to be_nil
        expect(profile[:event_id]).not_to be_nil
        expect(profile[:platform]).to eq("ruby")
        expect(profile[:version]).to eq("1")
        expect(profile[:release]).to eq("test-release")

        # Verify profile data structure
        expect(profile[:profile]).to include(
          :frames,
          :stacks,
          :samples,
          :thread_metadata
        )

        # Verify we have meaningful samples
        expect(profile[:profile][:samples].length).to be > 0
        expect(profile[:profile][:frames].length).to be > 0
        expect(profile[:profile][:stacks].length).to be > 0
      end
    end
  end
end
