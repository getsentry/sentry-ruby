# frozen_string_literal: true

SimpleCov.command_name "StdLibLogger"

RSpec.describe Sentry::StdLibLogger do
  let(:logger) { ::Logger.new($stdout) }

  context "when logger patch is enabled but enable_logs is turned off" do
    it "logs a warning message" do
      string_io = StringIO.new

      perform_basic_setup do |config|
        config.enable_logs = false
        config.enabled_patches = [:logger]
        config.sdk_logger = ::Logger.new(string_io)
      end

      expect(string_io.string).to include("WARN -- : :logger patch enabled but `enable_logs` is turned off - skipping applying patch")
    end
  end

  context "when enable_logs is set to true but logger patch is not enabled" do
    before do
      perform_basic_setup do |config|
        config.enable_logs = true
      end
    end

    it "does not send log using stdlib logger" do
      expect {
        logger.send(:info, "Hello World")
      }.to output(/Hello World/).to_stdout

      expect(sentry_logs).to be_empty
    end
  end

  context "when enable_logs is set to true and logger patch is set" do
    before do
      perform_basic_setup do |config|
        config.max_log_events = 1
        config.enable_logs = true
        config.enabled_patches = [:redis, :puma, :http, :logger]
      end
    end

    ["info", "warn", "error", "fatal"].each do |level|
      describe "##{level}" do
        it "send logs using stdlib logger" do
          expect {
            logger.send(level, "Hello World")
          }.to output(/Hello World/).to_stdout

          expect(sentry_logs).to_not be_empty

          log_event = sentry_logs.last

          expect(log_event[:level]).to eql(level)
          expect(log_event[:body]).to eql("Hello World")
        end
      end
    end

    context "when logger level is set to warn" do
      before do
        logger.level = ::Logger::WARN
      end

      it "should not send debug logs to Sentry when logger level is warn" do
        expect {
          logger.debug("Debug message")
        }.to_not output.to_stdout

        expect(sentry_logs).to be_empty
      end

      it "should not send info logs to Sentry when logger level is warn" do
        expect {
          logger.info("Info message")
        }.to_not output.to_stdout

        expect(sentry_logs).to be_empty
      end

      it "should send warn logs to Sentry when logger level is warn" do
        logger.warn("Warn message")

        expect(sentry_logs).to_not be_empty
        log_event = sentry_logs.last
        expect(log_event[:level]).to eql("warn")
        expect(log_event[:body]).to eql("Warn message")
      end

      it "should send error logs to Sentry when logger level is warn" do
        logger.error("Error message")

        expect(sentry_logs).to_not be_empty
        log_event = sentry_logs.last
        expect(log_event[:level]).to eql("error")
        expect(log_event[:body]).to eql("Error message")
      end
    end

    context "when logger level is set to error" do
      before do
        logger.level = ::Logger::ERROR
      end

      it "should not send warn logs to Sentry when logger level is error" do
        logger.warn("Warn message")

        expect(sentry_logs).to be_empty
      end

      it "should send error logs to Sentry when logger level is error" do
        logger.error("Error message")

        expect(sentry_logs).to_not be_empty
        log_event = sentry_logs.last
        expect(log_event[:level]).to eql("error")
        expect(log_event[:body]).to eql("Error message")
      end

      it "should send fatal logs to Sentry when logger level is error" do
        logger.fatal("Fatal message")

        expect(sentry_logs).to_not be_empty
        log_event = sentry_logs.last
        expect(log_event[:level]).to eql("fatal")
        expect(log_event[:body]).to eql("Fatal message")
      end
    end
  end
end
