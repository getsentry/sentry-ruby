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
          expect(log_event[:attributes]["sentry.origin"][:value]).to eq("auto.log.ruby.std_logger")
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

    context "with std_lib_logger_filter" do
      let(:null_logger) { ::Logger.new(IO::NULL) }

      context "when no filter is configured" do
        it "sends all log messages to Sentry" do
          logger.info("Test message")

          expect(sentry_logs).to_not be_empty
          expect(sentry_logs.last[:body]).to eq("Test message")
        end
      end

      context "when filter always returns true" do
        before do
          Sentry.configuration.std_lib_logger_filter = ->(logger, message, level) { true }
        end

        it "sends log messages to Sentry" do
          logger.info("Test message")

          expect(sentry_logs).to_not be_empty
          expect(sentry_logs.last[:body]).to eq("Test message")
        end
      end

      context "when filter always returns false" do
        before do
          Sentry.configuration.std_lib_logger_filter = ->(logger, message, level) { false }
        end

        it "blocks messages from Sentry but still logs locally" do
          expect {
            logger.info("Test message")
          }.to output(/Test message/).to_stdout

          expect(sentry_logs).to be_empty
        end
      end

      context "when filter uses logger instance for decisions" do
        before do
          Sentry.configuration.std_lib_logger_filter = ->(logger, message, level) do
            !logger.instance_variable_get(:@logdev).nil?
          end
        end

        it "allows logs from regular loggers" do
          logger.info("Regular log message")

          expect(sentry_logs).to_not be_empty
          expect(sentry_logs.last[:body]).to eq("Regular log message")
        end

        it "blocks logs from IO::NULL loggers" do
          null_logger.error("Null log message")

          expect(sentry_logs).to be_empty
        end
      end

      context "when filter uses message content for decisions" do
        before do
          Sentry.configuration.std_lib_logger_filter = ->(logger, message, level) do
            !message.to_s.include?("SKIP")
          end
        end

        it "allows messages without SKIP keyword" do
          logger.info("Regular info message")

          expect(sentry_logs).to_not be_empty
          expect(sentry_logs.last[:body]).to eq("Regular info message")
        end

        it "blocks messages containing SKIP keyword" do
          expect {
            logger.info("SKIP: this should be filtered")
          }.to output(/SKIP: this should be filtered/).to_stdout

          expect(sentry_logs).to be_empty
        end
      end

      context "when filter uses log level for decisions" do
        before do
          Sentry.configuration.std_lib_logger_filter = ->(logger, message, level) do
            [:error, :fatal].include?(level)
          end
        end

        it "allows error and fatal logs" do
          logger.error("Error message")
          logger.fatal("Fatal message")

          expect(sentry_logs.size).to eq(2)
          expect(sentry_logs[0][:body]).to eq("Error message")
          expect(sentry_logs[1][:body]).to eq("Fatal message")
        end

        it "blocks info and warn logs" do
          expect {
            logger.info("Info message")
            logger.warn("Warn message")
          }.to output(/Info message.*Warn message/m).to_stdout

          expect(sentry_logs).to be_empty
        end
      end
    end
  end
end
