# frozen_string_literal: true

RSpec.describe Sentry::DebugStructuredLogger do
  let(:configuration) do
    config = Sentry::Configuration.new
    config.enable_logs = true
    config.dsn = Sentry::TestHelper::DUMMY_DSN
    config
  end

  let(:debug_logger) { described_class.new(configuration) }

  before do
    debug_logger.clear
  end

  after do
    debug_logger.clear
  end

  describe "#initialize" do
    it "creates a debug logger with structured logger backend" do
      expect(debug_logger.backend).to be_a(Sentry::StructuredLogger)
    end

    it "creates a log file" do
      expect(debug_logger.log_file).to be_a(Pathname)
    end

    context "when logs are disabled" do
      let(:configuration) do
        config = Sentry::Configuration.new
        config.enable_logs = false
        config.dsn = Sentry::TestHelper::DUMMY_DSN
        config
      end

      it "creates a no-op logger backend" do
        expect(debug_logger.backend).to be_a(Sentry::DebugStructuredLogger::NoOpLogger)
      end
    end
  end

  describe "logging methods" do
    %i[trace debug info warn error fatal].each do |level|
      describe "##{level}" do
        it "captures log events to file" do
          debug_logger.public_send(level, "Test #{level} message", test_attr: "value")

          logged_events = debug_logger.logged_events
          expect(logged_events).not_to be_empty

          log_event = logged_events.last
          expect(log_event["level"]).to eq(level.to_s)
          expect(log_event["message"]).to eq("Test #{level} message")
          expect(log_event["attributes"]["test_attr"]).to eq("value")
          expect(log_event["timestamp"]).to be_a(String)
        end

        it "handles parameters correctly" do
          debug_logger.public_send(level, "Test message", ["param1", "param2"], extra_attr: "extra")

          logged_events = debug_logger.logged_events
          log_event = logged_events.last

          expect(log_event["parameters"]).to eq(["param1", "param2"])
          expect(log_event["attributes"]["extra_attr"]).to eq("extra")
        end
      end
    end
  end

  describe "#log" do
    it "captures log events with specified level" do
      debug_logger.log(:info, "Test log message", parameters: [], custom_attr: "custom_value")

      logged_events = debug_logger.logged_events
      expect(logged_events).not_to be_empty

      log_event = logged_events.last
      expect(log_event["level"]).to eq("info")
      expect(log_event["message"]).to eq("Test log message")
      expect(log_event["attributes"]["custom_attr"]).to eq("custom_value")
    end
  end

  describe "#logged_events" do
    it "returns empty array when no events logged" do
      expect(debug_logger.logged_events).to eq([])
    end

    it "returns all logged events" do
      debug_logger.info("First message")
      debug_logger.warn("Second message")
      debug_logger.error("Third message")

      logged_events = debug_logger.logged_events
      expect(logged_events.length).to eq(3)

      expect(logged_events[0]["message"]).to eq("First message")
      expect(logged_events[1]["message"]).to eq("Second message")
      expect(logged_events[2]["message"]).to eq("Third message")
    end
  end

  describe "#clear" do
    it "clears logged events" do
      debug_logger.info("Test message")
      expect(debug_logger.logged_events).not_to be_empty

      debug_logger.clear
      expect(debug_logger.logged_events).to be_empty
    end
  end

  describe "JSON serialization" do
    it "handles complex data types" do
      debug_logger.info("Complex data",
        string: "text",
        number: 42,
        boolean: true,
        array: [1, 2, 3],
        hash: { nested: "value" }
      )

      logged_events = debug_logger.logged_events
      log_event = logged_events.last

      expect(log_event["attributes"]["string"]).to eq("text")
      expect(log_event["attributes"]["number"]).to eq(42)
      expect(log_event["attributes"]["boolean"]).to eq(true)
      expect(log_event["attributes"]["array"]).to eq([1, 2, 3])
      expect(log_event["attributes"]["hash"]).to eq({ "nested" => "value" })
    end
  end
end
