# frozen_string_literal: true

require "spec_helper"

return if RAILS_VERSION < 7.1

begin
  require "good_job"
rescue LoadError
  return
end

GOOD_JOB_ADAPTER_FOR_TEST = ::ActiveJob::QueueAdapters::GoodJobAdapter.new(execution_mode: :external)

RSpec.describe "Sentry + ActiveJob on GoodJob", type: :job do
  include ActiveSupport::Testing::TimeHelpers
  include_context "active_job backend harness", adapter: :good_job
  include_context "good_job database"

  def queue_adapter_for_test
    GOOD_JOB_ADAPTER_FOR_TEST
  end

  def boot_adapter(_adapter)
    Sentry::Rails::Test::GoodJobDatabase.connect
  end

  def reset_adapter(_adapter)
    GoodJob::Execution.delete_all
    GoodJob::Job.delete_all
  end

  def drain(at: nil)
    run = lambda do
      lock_id = SecureRandom.uuid

      loop do
        result = GoodJob::Job.perform_with_advisory_lock(lock_id: lock_id)
        break if result.nil?
        raise result.unhandled_error if result.unhandled_error
      end
    end

    at ? travel_to(at, &run) : run.call
  end

  def last_enqueued_payload
    GoodJob::Job.order(:created_at).last&.serialized_params
  end

  it_behaves_like "a Sentry-instrumented ActiveJob backend"
  it_behaves_like "an ActiveJob backend that supports distributed tracing"

  context "with tracing enabled" do
    let(:configure_sentry) { proc { |config| config.traces_sample_rate = 1.0 } }

    let(:good_job_job) do
      job_fixture do
        self.queue_adapter = GOOD_JOB_ADAPTER_FOR_TEST

        def perform; end
      end
    end

    it "records GoodJob messaging data on both ends of a job and continues the enqueuing trace" do
      parent_trace_id = nil

      within_parent_transaction do |parent|
        parent_trace_id = parent.trace_id
        good_job_job.set(queue: "mailers").perform_later
      end
      drain

      publish_span = transactions.flat_map(&:spans).find { |s| s[:op] == "queue.publish" }
      consumer_data = consumer_transaction.contexts.dig(:trace, :data)
      job_id = GoodJob::Job.first.active_job_id

      expect(publish_span[:data]).to include(
        "messaging.system" => "good_job",
        "messaging.message.id" => job_id,
        "messaging.destination.name" => "mailers"
      )
      expect(consumer_data).to include(
        "messaging.system" => "good_job",
        "messaging.message.id" => job_id,
        "messaging.destination.name" => "mailers"
      )
      expect(consumer_transaction.contexts.dig(:trace, :trace_id)).to eq(parent_trace_id)
      expect(consumer_transaction.contexts.dig(:trace, :parent_span_id)).to eq(publish_span[:span_id])
    end
  end
end
