# frozen_string_literal: true

require "rails"
require "securerandom"

return if Rails.version.to_f < 7.2

begin
  require "mock_redis"
  require "resque"
  require "resque-scheduler"
rescue LoadError
  return
end

require_relative "support/rails_app"

RSpec.describe "ActiveJob jobs on Resque with sentry-resque loaded", type: :job do
  include ActiveSupport::Testing::TimeHelpers
  include_context "active_job backend harness", adapter: :resque
  include_context "resque adapter"

  let(:job_span_origin) { "auto.queue.resque" }
  let(:skipped_adapter_error_events) { 1 }

  def expected_message_body_size(delivered_job_data)
    Resque.encode("class" => ActiveJob::QueueAdapters::ResqueAdapter::JobWrapper.name, "args" => [delivered_job_data]).bytesize
  end

  it_behaves_like "a Sentry-instrumented ActiveJob backend"
  it_behaves_like "an ActiveJob backend that supports distributed tracing"

  context "with the resque adapter opted in to the ActiveJob integration" do
    let(:configure_sentry) { proc { |config| config.traces_sample_rate = 1.0 } }

    def error_events
      sentry_events.grep(Sentry::ErrorEvent)
    end

    it "reports a failing job once, within one consumer transaction that keeps the sentry-resque identity" do
      failing_job.set(queue: "events").perform_later

      expect { drain }.to raise_error(RuntimeError, /boom from failing_job spec/)

      consumer_transactions = transactions.select { |t| t.contexts.dig(:trace, :op) == "queue.process" }
      expect(consumer_transactions.size).to eq(1)
      expect(error_events.size).to eq(1)

      transaction = consumer_transactions.first
      error_event = error_events.first
      expect(transaction.contexts.dig(:trace, :origin)).to eq("auto.queue.resque")
      expect(transaction.tags).to include("resque.queue" => "events")
      expect(transaction.contexts[:"Active-Job"]).to include(job_class: failing_job.name, queue: "events")
      expect(error_event.tags).to include("resque.queue" => "events")
      expect(error_event.contexts[:"Active-Job"]).to include(job_class: failing_job.name, queue: "events")
      expect(error_event.sdk[:name]).to eq("sentry.ruby.resque")
    end

    it "should report an error raised before a job whose class was removed can run once through sentry-resque" do
      job = successful_job.set(queue: "events").perform_later
      hide_const(job.class.name)

      expect { drain }.to raise_error(NameError)

      expect(error_events.size).to eq(1)
      expect(error_events.first.sdk[:name]).to eq("sentry.ruby.resque")
      expect(error_events.first.tags).to include("resque.queue" => "events")
      expect(error_events.first.contexts[:"Active-Job"]).to include(job_class: job.class.name, queue: "events")
    end

    it "includes the job arguments in the Active-Job context only when queue data collection is on" do
      [true, false].each do |collect_queues|
        Sentry.configuration.data_collection.queues = collect_queues
        sentry_events.clear
        failing_job.set(queue: "events").perform_later("hello")

        expect { drain }.to raise_error(RuntimeError, /boom from failing_job spec/)

        context = error_events.first.contexts[:"Active-Job"]
        expect(context).to include(job_class: failing_job.name, queue: "events", executions: 0, locale: "en")
        if collect_queues
          expect(context[:arguments]).to eq(["hello"])
        else
          expect(context).not_to have_key(:arguments)
        end
      end
    end

    it "should keep recording plain Resque jobs in a queue.resque transaction" do
      plain_job = Class.new { def self.perform; end }
      stub_const("PlainResqueJob", plain_job)

      Resque::Job.create(:default, PlainResqueJob)
      drain

      expect(transactions.map { |event| event.contexts.dig(:trace, :op) }).to eq(["queue.resque"])
    end

    it "records the resque messaging attributes on the consumer transaction" do
      job = successful_job.set(queue: "events").perform_later
      drain

      expect(consumer_transaction.contexts.dig(:trace, :data)).to include(
        "messaging.system" => "resque",
        "messaging.message.id" => job.job_id,
        "messaging.destination.name" => "events"
      )
    end

    it "records messaging.system resque on the queue.publish producer span" do
      within_parent_transaction { successful_job.perform_later }

      parent = transactions.find { |t| t.contexts.dig(:trace, :op) == "test" }
      publish_span = parent.spans.find { |span| span[:op] == "queue.publish" }
      expect(publish_span[:data]).to include("messaging.system" => "resque")
    end
  end
end
