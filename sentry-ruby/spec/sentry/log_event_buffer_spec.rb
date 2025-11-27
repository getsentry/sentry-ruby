# frozen_string_literal: true

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
      config.enable_logs = true
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
      expect(client).to_not receive(:send_logs)

      2.times { log_event_buffer.add_event(log_event) }
    end

    it "auto-flushes pending events to the client when the number of events reaches max_events" do
      expect(client).to receive(:send_logs)

      3.times { log_event_buffer.add_event(log_event) }

      expect(log_event_buffer).to be_empty
    end
  end

  describe "multi-threaded access" do
    let(:max_log_events) { 30 }

    it "thread-safely handles concurrent access" do
      expect(client).to receive(:send_logs).exactly(3).times

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

  describe "error handling" do
    let(:max_log_events) { 3 }

    let(:error) { Errno::ECONNREFUSED.new("Connection refused") }

    context "when send_logs raises an exception" do
      before do
        allow(client).to receive(:send_logs).and_raise(error)
      end

      it "does not propagate exception from add_event when buffer is full" do
        expect {
          3.times { log_event_buffer.add_event(log_event) }
        }.not_to raise_error
      end

      it "does not propagate exception from flush" do
        2.times { log_event_buffer.add_event(log_event) }

        expect {
          log_event_buffer.flush
        }.not_to raise_error
      end

      it "logs the error to sdk_logger" do
        3.times { log_event_buffer.add_event(log_event) }

        expect(string_io.string).to include("Failed to send logs")
      end

      it "clears the buffer after a failed send to avoid memory buildup" do
        3.times { log_event_buffer.add_event(log_event) }

        expect(log_event_buffer).to be_empty
      end
    end

    context "when background thread encounters an error" do
      let(:max_log_events) { 100 }

      before do
        allow(client).to receive(:send_logs).and_raise(error)
      end

      it "keeps the background thread alive after an error" do
        log_event_buffer.add_event(log_event)
        log_event_buffer.start

        thread = log_event_buffer.instance_variable_get(:@thread)

        expect(thread).to be_alive
        expect { log_event_buffer.flush }.not_to raise_error
        expect(thread).to be_alive
      end
    end
  end
end
