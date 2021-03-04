require "spec_helper"
require 'sidekiq/manager'

RSpec.describe Sentry::Sidekiq do
  before do
    perform_basic_setup
  end

  after do
    # those test jobs will go into the real Redis and be visiable to other sidekiq processes
    # this can affect local testing and development, so we should clear them after each test
    Sidekiq::RetrySet.new.clear
  end

  let(:processor) do
    opts = { :queues => ['default'] }
    manager = Sidekiq::Manager.new(opts)
    manager.workers.first
  end

  let(:transport) do
    Sentry.get_current_client.transport
  end

  it "registers error handlers and middlewares" do
    expect(Sidekiq.error_handlers).to include(described_class::ErrorHandler)
    expect(Sidekiq.server_middleware.entries.first.klass).to eq(described_class::SentryContextMiddleware)
  end

  it "captues exception raised in the worker" do
    expect { process_job(processor, "SadWorker") }.to change { transport.events.size }.by(1)

    event = transport.events.last.to_hash
    expect(event[:sdk]).to eq({ name: "sentry.ruby.sidekiq", version: described_class::VERSION })
    expect(Sentry::Event.get_message_from_exception(event)).to eq("RuntimeError: I'm sad!")
  end

  describe "context cleanup" do
    it "cleans up context from processed jobs" do
      process_job(processor, "HappyWorker")
      process_job(processor, "SadWorker")

      expect(transport.events.count).to eq(1)
      event = transport.events.last.to_json_compatible

      expect(event["tags"]).to eq("queue" => "default", "jid" => "123123", "mood" => "sad")
      expect(event["transaction"]).to eq("Sidekiq/SadWorker")
      expect(event["breadcrumbs"]["values"][0]["message"]).to eq("I'm sad!")
    end

    it "cleans up context from failed jobs" do
      process_job(processor, "SadWorker")
      process_job(processor, "VerySadWorker")

      expect(transport.events.count).to eq(2)
      event = transport.events.last.to_json_compatible

      expect(event["tags"]).to eq("queue" => "default", "jid" => "123123", "mood" => "very sad")
      expect(event["breadcrumbs"]["values"][0]["message"]).to eq("I'm very sad!")
    end
  end

  it "has some context when capturing, even if no exception raised" do
    process_job(processor, "ReportingWorker")

    event = transport.events.last.to_json_compatible

    expect(event["message"]).to eq "I have something to say!"
    expect(event["extra"]["sidekiq"]).to eq("class" => "ReportingWorker", "jid" => "123123", "queue" => "default")
  end

  it "adds the failed job to the retry queue" do
    process_job(processor, "SadWorker")

    retries = Sidekiq::RetrySet.new
    expect(retries.count).to eq(1)
  end

  context "when tracing is enabled" do
    before do
      perform_basic_setup do |config|
        config.traces_sample_rate = 1.0
      end
    end

    it "records transaction" do
      process_job(processor, "HappyWorker")

      expect(transport.events.count).to eq(1)
      transaction = transport.events.first

      expect(transaction.transaction).to eq("Sidekiq/HappyWorker")
      expect(transaction.contexts.dig(:trace, :trace_id)).to be_a(String)
      expect(transaction.contexts.dig(:trace, :span_id)).to be_a(String)
      expect(transaction.contexts.dig(:trace, :status)).to eq("ok")
    end

    it "records transaction with exception" do
      process_job(processor, "SadWorker")

      expect(transport.events.count).to eq(2)
      transaction = transport.events.first

      expect(transaction.transaction).to eq("Sidekiq/SadWorker")
      expect(transaction.contexts.dig(:trace, :trace_id)).to be_a(String)
      expect(transaction.contexts.dig(:trace, :span_id)).to be_a(String)
      expect(transaction.contexts.dig(:trace, :status)).to eq("internal_error")

      event = transport.events.last
      expect(event.contexts.dig(:trace, :trace_id)).to eq(transaction.contexts.dig(:trace, :trace_id))
    end
  end
end

