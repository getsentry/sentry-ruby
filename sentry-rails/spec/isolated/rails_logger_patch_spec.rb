# frozen_string_literal: true

begin
  require "simplecov"
  SimpleCov.command_name "RailsLoggerPatch"
rescue LoadError
end

require "logger"
require "sentry-ruby"
require "sentry/test_helper"

require_relative "../dummy/test_rails_app/app"

RSpec.describe "Rails.logger with :logger patch" do
  include Sentry::TestHelper

  let!(:app) do
    make_basic_app do |config, app|
      config.enable_logs = true
      config.enabled_patches = [:logger]
      config.max_log_events = 10
      config.sdk_logger = Logger.new(nil)

      app.config.log_level = log_level
    end
  end

  let(:log_level) { ::Logger::DEBUG }
  let(:log_output) { StringIO.new }

  before do
    Rails.logger = Logger.new(log_output)
    Rails.logger.level = log_level
  end

  context "when :logger patch is enabled" do
    it "captures Rails.logger calls when :logger patch is enabled" do
      Rails.logger.debug("Test debug message")
      Rails.logger.info("Test info message")
      Rails.logger.warn("Test warning message")
      Rails.logger.error("Test error message")
      Rails.logger.fatal("Test fatal message")

      Sentry.get_current_client.log_event_buffer.flush

      expect(sentry_logs).not_to be_empty

      log_messages = sentry_logs.map { |log| log[:body] }
      expect(log_messages).to include(
        "Test debug message",
        "Test info message",
        "Test warning message",
        "Test error message",
        "Test fatal message"
      )

      test_logs = sentry_logs.select { |log| log[:body].start_with?("Test ") }
      log_levels = test_logs.map { |log| log[:level] }
      expect(log_levels).to contain_exactly("debug", "info", "warn", "error", "fatal")
    end

    it "captures Rails.logger calls with block syntax" do
      Rails.logger.info { "Block message" }

      Sentry.get_current_client.log_event_buffer.flush

      expect(sentry_logs).not_to be_empty

      log_messages = sentry_logs.map { |log| log[:body] }
      expect(log_messages).to include("Block message")

      block_log = sentry_logs.find { |log| log[:body] == "Block message" }
      expect(block_log[:level]).to eq("info")
    end

    it "captures Rails.logger calls with progname" do
      Rails.logger.info("MyProgram") { "Message with progname" }

      Sentry.get_current_client.log_event_buffer.flush

      expect(sentry_logs).not_to be_empty

      log_messages = sentry_logs.map { |log| log[:body] }
      expect(log_messages).to include("Message with progname")

      progname_log = sentry_logs.find { |log| log[:body] == "Message with progname" }
      expect(progname_log[:level]).to eq("info")
    end

    it "does not capture Sentry SDK internal logs" do
      Rails.logger.info(Sentry::Logger::PROGNAME) { "Internal Sentry message" }

      Sentry.get_current_client.log_event_buffer.flush

      log_messages = sentry_logs.map { |log| log[:body] }
      expect(log_messages).not_to include("Internal Sentry message")
    end

    it "strips whitespace from log messages" do
      Rails.logger.info("  Message with whitespace  ")

      Sentry.get_current_client.log_event_buffer.flush

      expect(sentry_logs).not_to be_empty

      log_messages = sentry_logs.map { |log| log[:body] }
      expect(log_messages).to include("Message with whitespace")
    end

    it "handles non-string log messages" do
      Rails.logger.info(12345)

      Sentry.get_current_client.log_event_buffer.flush

      expect(sentry_logs).not_to be_empty

      log_messages = sentry_logs.map { |log| log[:body] }
      expect(log_messages).to include("12345")
    end

    context "when Rails logger level is configured to warn" do
      let(:log_level) { ::Logger::WARN }

      it "does not send debug logs to Sentry when Rails logger level is warn" do
        expect {
          Rails.logger.debug("Debug message should not be sent")
        }.not_to output.to_stdout

        Sentry.get_current_client.log_event_buffer.flush

        log_messages = sentry_logs.map { |log| log[:body] }
        expect(log_messages).not_to include("Debug message should not be sent")
      end

      it "does not send info logs to Sentry when Rails logger level is warn" do
        expect {
          Rails.logger.info("Info message should not be sent")
        }.not_to output.to_stdout

        Sentry.get_current_client.log_event_buffer.flush

        log_messages = sentry_logs.map { |log| log[:body] }
        expect(log_messages).not_to include("Info message should not be sent")
      end

      it "sends warn logs to Sentry when Rails logger level is warn" do
        Rails.logger.warn("Warn message should be sent")

        Sentry.get_current_client.log_event_buffer.flush

        expect(sentry_logs).not_to be_empty

        log_messages = sentry_logs.map { |log| log[:body] }
        expect(log_messages).to include("Warn message should be sent")

        warn_log = sentry_logs.find { |log| log[:body] == "Warn message should be sent" }
        expect(warn_log[:level]).to eq("warn")
      end

      it "sends error logs to Sentry when Rails logger level is warn" do
        Rails.logger.error("Error message should be sent")

        Sentry.get_current_client.log_event_buffer.flush

        expect(sentry_logs).not_to be_empty

        log_messages = sentry_logs.map { |log| log[:body] }
        expect(log_messages).to include("Error message should be sent")

        error_log = sentry_logs.find { |log| log[:body] == "Error message should be sent" }
        expect(error_log[:level]).to eq("error")
      end
    end

    context "when Rails logger level is configured to error" do
      let(:log_level) { ::Logger::ERROR }

      it "does not send warn logs to Sentry when Rails logger level is error" do
        expect {
          Rails.logger.warn("Warn message should not be sent")
        }.not_to output.to_stdout

        Sentry.get_current_client.log_event_buffer.flush

        log_messages = sentry_logs.map { |log| log[:body] }
        expect(log_messages).not_to include("Warn message should not be sent")
      end

      it "sends error logs to Sentry when Rails logger level is error" do
        Rails.logger.error("Error message should be sent")

        Sentry.get_current_client.log_event_buffer.flush

        expect(sentry_logs).not_to be_empty

        log_messages = sentry_logs.map { |log| log[:body] }
        expect(log_messages).to include("Error message should be sent")

        error_log = sentry_logs.find { |log| log[:body] == "Error message should be sent" }
        expect(error_log[:level]).to eq("error")
      end
    end
  end

  context "when Rails.logger is a BroadcastLogger", skip: !defined?(ActiveSupport::BroadcastLogger) do
    let(:string_io1) { StringIO.new }
    let(:string_io2) { StringIO.new }
    let(:logger1) { Logger.new(string_io1) }
    let(:logger2) { Logger.new(string_io2) }
    let(:broadcast_logger) { ActiveSupport::BroadcastLogger.new(logger1, logger2) }
    let(:broadcast_app) do
      make_basic_app do |config|
        config.enable_logs = true
        config.enabled_patches = [:logger]
        config.max_log_events = 10
        config.sdk_logger = Logger.new(nil)
      end
    end

    before do
      broadcast_app
      Rails.logger = broadcast_logger
    end

    it "captures logs from BroadcastLogger" do
      Rails.logger.info("Broadcast message")

      Sentry.get_current_client.log_event_buffer.flush

      expect(sentry_logs).not_to be_empty

      log_messages = sentry_logs.map { |log| log[:body] }
      expect(log_messages).to include("Broadcast message")

      broadcast_log = sentry_logs.find { |log| log[:body] == "Broadcast message" }
      expect(broadcast_log[:level]).to eq("info")

      expect(string_io1.string).to include("Broadcast message")
      expect(string_io2.string).to include("Broadcast message")
    end
  end
end
