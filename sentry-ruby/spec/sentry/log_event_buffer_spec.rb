# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sentry::LogEventBuffer do
  subject(:log_event_buffer) { described_class.new(Sentry.configuration, client) }

  let(:string_io) { StringIO.new }
  let(:logger) { ::Logger.new(string_io) }

  before do
    perform_basic_setup do |config|
      config.logger = logger
      config.background_worker_threads = 0
      config.max_log_events = 3
    end

    Sentry.background_worker = Sentry::BackgroundWorker.new(Sentry.configuration)
  end

  after do
    Sentry.background_worker = Class.new { def shutdown; end; }.new
  end

  let(:client) { Sentry.get_current_client }
  let(:transport) { client.transport }

  describe "#add_event" do
    let(:log_event) do
      Sentry::LogEvent.new(
        configuration: Sentry.configuration,
        level: :info,
        body: "Test message"
      )
    end

    it "does nothing when there are no pending events" do
      expect(client).not_to receive(:capture_envelope)

      log_event_buffer.flush

      expect(sentry_envelopes.size).to be(0)
    end

    it "does nothing when the number of events is less than max_events " do
      2.times { log_event_buffer.add_event(log_event) }

      log_event_buffer.flush

      expect(sentry_envelopes.size).to be(0)
    end

    it "sends pending events to the client" do
      3.times { log_event_buffer.add_event(log_event) }

      log_event_buffer.flush

      expect(sentry_envelopes.size).to be(1)

      expect(log_event_buffer).to be_empty
    end

    it "thread-safely handles concurrent access" do
      expect(client).to receive(:send_envelope) do |_envelope|
        sleep 0.1
      end

      threads = 100.times.map do
        (1..50).to_a.sample.times { log_event_buffer.add_event(log_event) }

        Thread.new do
          log_event_buffer.flush
        end
      end

      threads.each(&:join)

      expect(log_event_buffer).to be_empty
    end
  end
end
