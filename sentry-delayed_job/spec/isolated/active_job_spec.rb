# frozen_string_literal: true

require "rails"
require "securerandom"

return if Rails.version.to_f < 7.2
return unless Gem.loaded_specs.key?("rspec-rails")

require_relative "support/rails_app"

RSpec.describe "ActiveJob jobs on delayed_job with sentry-delayed_job loaded", type: :job do
  include ActiveSupport::Testing::TimeHelpers
  include_context "active_job backend harness", adapter: :delayed_job
  include_context "delayed_job adapter"

  let(:job_span_origin) { "auto.queue.delayed_job" }

  it_behaves_like "a Sentry-instrumented ActiveJob backend"
  it_behaves_like "an ActiveJob backend that supports distributed tracing"

  context "with the delayed_job adapter opted in to the ActiveJob integration" do
    let(:configure_sentry) { proc { |config| config.traces_sample_rate = 1.0 } }

    before { Delayed::Worker.logger = Logger.new(nil) }

    def work_off
      Delayed::Job.order(:id).each { |record| Delayed::Worker.new.run(record) }
    end

    def error_events
      sentry_events.grep(Sentry::ErrorEvent)
    end

    def transactions_with_op(op)
      transactions.select { |transaction| transaction.contexts.dig(:trace, :op) == op }
    end

    it "reports a failing job once, within one consumer transaction that keeps the sentry-delayed_job identity" do
      failing_job.set(queue: "events").perform_later

      work_off

      expect(transactions_with_op("queue.process").size).to eq(1)
      expect(transactions_with_op("queue.delayed_job")).to be_empty
      expect(error_events.size).to eq(1)

      transaction = transactions_with_op("queue.process").first
      error_event = error_events.first
      expect(transaction.contexts.dig(:trace, :origin)).to eq("auto.queue.delayed_job")
      expect(transaction.tags).to include("delayed_job.queue" => "events")
      expect(transaction.contexts[:"Active-Job"]).to include(job_class: failing_job.name, queue_name: "events")
      expect(error_event.tags).to include("delayed_job.queue" => "events")
      expect(error_event.contexts[:"Active-Job"]).to include(job_class: failing_job.name, queue_name: "events")
      expect(error_event.sdk[:name]).to eq("sentry.ruby.delayed_job")
    end

    it "should report an error raised before a job whose class was removed can run once through sentry-delayed_job" do
      job = successful_job.set(queue: "events").perform_later
      hide_const(job.class.name)

      work_off

      expect(error_events.size).to eq(1)
      expect(error_events.first.sdk[:name]).to eq("sentry.ruby.delayed_job")
      expect(error_events.first.tags).to include("delayed_job.queue" => "events")
      expect(error_events.first.contexts[:"Active-Job"]).to include(job_class: job.class.name, queue_name: "events")
    end

    it "should report an error raised before a job runs with the plugin's Active-Job context, without sentry's internal payload data" do
      Sentry.configuration.data_collection.queues = false
      job = successful_job.set(queue: "events").perform_later("job argument")
      expect(Delayed::Job.order(:id).last.payload_object.job_data).to have_key("_sentry")
      hide_const(job.class.name)

      work_off

      context = error_events.first.contexts[:"Active-Job"]
      expect(context).to include(job_class: job.class.name, job_id: job.job_id, arguments: ["job argument"])
      expect(context).not_to have_key(:_sentry)
    end

    it "includes the job arguments in the Active-Job context only when queue data collection is on" do
      [true, false].each do |collect_queues|
        Sentry.configuration.data_collection.queues = collect_queues
        sentry_events.clear
        Delayed::Job.delete_all
        failing_job.set(queue: "events").perform_later("hello")

        work_off

        context = error_events.first.contexts[:"Active-Job"]
        expect(context).to include(job_class: failing_job.name, queue_name: "events")
        expect(context).not_to have_key(:_sentry)
        if collect_queues
          expect(context[:arguments]).to eq(["hello"])
        else
          expect(context).not_to have_key(:arguments)
        end
      end
    end

    it "should keep recording plain delayed_job jobs in a queue.delayed_job transaction" do
      stub_const("PlainDelayedJob", Struct.new(:id) { def perform; end })

      Delayed::Job.enqueue(PlainDelayedJob.new(1))
      work_off

      expect(transactions.map { |event| event.contexts.dig(:trace, :op) }).to eq(["queue.delayed_job"])
    end

    it "tags the transaction and the error event with the delayed_job record id, as the plugin does" do
      failing_job.set(queue: "events").perform_later
      record_id = Delayed::Job.order(:id).last.id.to_s

      work_off

      expect(transactions_with_op("queue.process").first.tags).to include("delayed_job.id" => record_id)
      expect(error_events.first.tags).to include("delayed_job.id" => record_id)
    end

    it "records the delayed_job messaging attributes on the consumer transaction" do
      job = successful_job.set(queue: "events").perform_later
      work_off

      expect(transactions_with_op("queue.process").first.contexts.dig(:trace, :data)).to include(
        "messaging.system" => "delayed_job",
        "messaging.message.id" => job.job_id,
        "messaging.destination.name" => "events"
      )
    end
  end
end
