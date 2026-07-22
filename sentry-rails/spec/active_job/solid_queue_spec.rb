# frozen_string_literal: true

require "spec_helper"

if RAILS_VERSION >= 7.1 && RUBY_VERSION >= "3.1"
  require "solid_queue"

  RSpec.describe "Sentry + ActiveJob on SolidQueue", type: :job do
    include ActiveSupport::Testing::TimeHelpers
    include_context "active_job backend harness", adapter: :solid_queue

    # Instantiated once. Each SolidQueueAdapter.new registers a
    # SolidQueue.on_worker_stop callback at class-load time (mutating
    # global SolidQueue state), so creating a fresh adapter per example
    # would accumulate callbacks across the run.
    SOLID_QUEUE_ADAPTER_FOR_TEST = ::ActiveJob::QueueAdapters::SolidQueueAdapter.new

    def queue_adapter_for_test
      SOLID_QUEUE_ADAPTER_FOR_TEST
    end

    def boot_adapter(_adapter)
      Sentry::Rails::Test::Application.load_queue_schema
    end

    def reset_adapter(_adapter)
      [
        SolidQueue::ReadyExecution,
        SolidQueue::ClaimedExecution,
        SolidQueue::FailedExecution,
        SolidQueue::BlockedExecution,
        SolidQueue::ScheduledExecution,
        SolidQueue::RecurringExecution,
        SolidQueue::Process,
        SolidQueue::Job
      ].each(&:delete_all)
    end

    def drain(at: nil)
      process = SolidQueue::Process.register(
        kind: "Worker",
        pid: ::Process.pid,
        name: "spec-#{SecureRandom.hex(4)}"
      )

      # Loop until both ready and scheduled tables are empty so that
      # retry_on cascades cleanly: a failing perform pushes the job into
      # SolidQueue::ScheduledExecution (via enqueue_at), which the next
      # iteration promotes to ReadyExecution and claims for execution.
      # A single dispatch+claim pass would only observe the first
      # attempt.
      run = lambda do
        loop do
          SolidQueue::ScheduledExecution.dispatch_next_batch(100)
          ready = SolidQueue::ReadyExecution.claim("*", 100, process.id)
          break if ready.empty? && SolidQueue::ScheduledExecution.none?
          ready.each(&:perform)
        end
      end

      # Only wrap in travel_to when the caller explicitly asks for a future
      # time — otherwise nested travel_to (e.g. from a spec that already
      # called `travel`) raises.
      at ? travel_to(at, &run) : run.call
    end

    def last_enqueued_payload
      SolidQueue::Job.order(:id).last&.arguments
    end

    it_behaves_like "a Sentry-instrumented ActiveJob backend"
    it_behaves_like "an ActiveJob backend that supports distributed tracing"

    context "adapter-generated span parentage" do
      let(:configure_sentry) { proc { |config| config.traces_sample_rate = 1.0 } }

      it "nests the Solid Queue enqueue DB span directly under the queue.publish span" do
        within_parent_transaction do
          successful_job.perform_later
        end

        parent = transactions.find { |t| t.contexts.dig(:trace, :op) == "test" }
        publish_span = parent.spans.find { |s| s[:op] == "queue.publish" }
        expect(publish_span).not_to be_nil

        enqueue_db_span = parent.spans.find do |s|
          s[:op] == "db.sql.active_record" && s[:parent_span_id] == publish_span[:span_id]
        end
        expect(enqueue_db_span).not_to be_nil
      end

      it "nests a job-body DB span directly under the queue.process consumer transaction" do
        db_job = job_fixture do
          def perform
            SolidQueue::Job.count
          end
        end

        db_job.perform_later
        drain

        expect(consumer_transaction).not_to be_nil

        consumer_span_id = consumer_transaction.contexts.dig(:trace, :span_id)
        body_db_span = consumer_transaction.spans.find do |s|
          s[:op] == "db.sql.active_record" && s[:parent_span_id] == consumer_span_id
        end
        expect(body_db_span).not_to be_nil
      end
    end
  end
end
