# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sentry::Resque do
  before do
    perform_basic_setup do |config|
      config.traces_sample_rate = 1.0
    end
  end

  class FailedJob
    def self.perform
      1/0
    end
  end

  class MessageJob
    def self.perform(msg)
      Sentry.capture_message(msg)
    end
  end

  let(:worker) do
    Resque::Worker.new(:default)
  end

  let(:transport) do
    Sentry.get_current_client.transport
  end

  it "records tracing events" do
    Resque::Job.create(:default, MessageJob, "report")

    worker.work(0)

    expect(transport.events.count).to eq(2)
    event = transport.events.first.to_hash
    expect(event[:message]).to eq("report")

    tracing_event = transport.events.last.to_hash
    expect(tracing_event[:transaction]).to eq("MessageJob")
    expect(tracing_event[:transaction_info]).to eq({ source: :task })
    expect(tracing_event[:type]).to eq("transaction")
    expect(tracing_event.dig(:contexts, :trace, :status)).to eq("ok")
    expect(tracing_event.dig(:contexts, :trace, :op)).to eq("queue.resque")
    expect(tracing_event.dig(:contexts, :trace, :origin)).to eq("auto.queue.resque")
  end

  it "records tracing events with exceptions" do
    Resque::Job.create(:default, FailedJob)

    worker.work(0)

    expect(transport.events.count).to eq(2)
    event = transport.events.first.to_hash
    expect(event.dig(:exception, :values, 0, :type)).to eq("ZeroDivisionError")

    tracing_event = transport.events.last.to_hash
    expect(tracing_event[:transaction]).to eq("FailedJob")
    expect(tracing_event[:transaction_info]).to eq({ source: :task })
    expect(tracing_event[:type]).to eq("transaction")
    expect(tracing_event.dig(:contexts, :trace, :status)).to eq("internal_error")
    expect(tracing_event.dig(:contexts, :trace, :op)).to eq("queue.resque")
    expect(tracing_event.dig(:contexts, :trace, :origin)).to eq("auto.queue.resque")
  end

  context "with instrumenter :otel" do
    before do
      perform_basic_setup do |config|
        config.traces_sample_rate = 1.0
        config.instrumenter = :otel
      end
    end

    it "does not record transaction" do
      Resque::Job.create(:default, MessageJob, "report")
      worker.work(0)

      expect(transport.events.count).to eq(1)
      event = transport.events.first.to_hash
      expect(event[:message]).to eq("report")
    end
  end
end
