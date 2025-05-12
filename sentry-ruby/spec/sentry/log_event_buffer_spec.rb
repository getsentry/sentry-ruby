# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sentry::LogEventBuffer do
  subject(:log_event_buffer) { described_class.new(Sentry.configuration, client) }

  let(:string_io) { StringIO.new }
  let(:logger) { ::Logger.new(string_io) }
  let(:client) { double(Sentry::Client) }
  let(:log_event) do
    Sentry::LogEvent.new(
      configuration: Sentry.configuration,
      level: :info,
      body: "Test message"
    )
  end

  before do
    perform_basic_setup do |config|
      config.sdk_logger = logger
      config.background_worker_threads = 0
      config.max_log_events = max_log_events
    end

    Sentry.background_worker = Sentry::BackgroundWorker.new(Sentry.configuration)
  end

  after do
    Sentry.background_worker = Class.new { def shutdown; end; }.new
  end

  describe "#add_event" do
    let(:max_log_events) { 3 }

    it "does nothing when there are no pending events" do
      expect(client).not_to receive(:capture_envelope)

      log_event_buffer.flush

      expect(sentry_envelopes.size).to be(0)
    end

    it "does nothing when the number of events is less than max_events " do
      expect(client).to_not receive(:send_envelope)

      2.times { log_event_buffer.add_event(log_event) }
    end

    it "auto-flushes pending events to the client when the number of events reaches max_events" do
      expect(client).to receive(:send_envelope)

      3.times { log_event_buffer.add_event(log_event) }

      expect(log_event_buffer).to be_empty
    end
  end

  describe "multi-threaded access" do
    let(:max_log_events) { 30 }

    it "thread-safely handles concurrent access" do
      expect(client).to receive(:send_envelope).exactly(3).times

      threads = 3.times.map do
        Thread.new do
          (20..30).to_a.sample.times { log_event_buffer.add_event(log_event) }
        end
      end

      threads.each(&:join)

      log_event_buffer.flush

      expect(log_event_buffer).to be_empty
    end
  end
end
