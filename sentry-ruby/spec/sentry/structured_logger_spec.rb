# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sentry::StructuredLogger do
  context "when enable_logs is set to false" do
    before do
      perform_basic_setup do |config|
        config.enable_logs = false
      end
    end

    it "configures default SDK logger" do
      expect(Sentry.logger).to be(Sentry.configuration.sdk_logger)
    end
  end

  context "when log events are enabled" do
    before do
      perform_basic_setup do |config|
        config.max_log_events = 1
        config.enable_logs = true
      end
    end

    ["info", "warn", "error", "fatal"].each do |level|
      describe "##{level}" do
        it "logs using default logger and LogEvent logger with extra attributes" do
          payload = { user_id: 123, action: "create" }

          Sentry.logger.public_send(level, "Hello World", payload)

          expect(sentry_logs).to_not be_empty

          log_event = sentry_logs.last

          expect(log_event[:level]).to eql(level)
          expect(log_event[:body]).to eql("Hello World")
          expect(log_event[:attributes]).to include({ user_id: { value: 123, type: "integer" } })
          expect(log_event[:attributes]).to include({ action: { value: "create", type: "string" } })
        end

        it "logs with template parameters" do
          Sentry.logger.public_send(level, "Hello %s it is %s", ["Jane", "Monday"])

          expect(sentry_logs).to_not be_empty

          log_event = sentry_logs.last

          expect(log_event[:level]).to eql(level)
          expect(log_event[:body]).to eql("Hello Jane it is Monday")
          expect(log_event[:attributes]["sentry.message.template"]).to eql({ value: "Hello %s it is %s", type: "string" })
          expect(log_event[:attributes]["sentry.message.parameters.0"]).to eql({ value: "Jane", type: "string" })
          expect(log_event[:attributes]["sentry.message.parameters.1"]).to eql({ value: "Monday", type: "string" })
        end

        it "logs with template parameters and extra attributres" do
          Sentry.logger.public_send(level, "Hello %s it is %s", ["Jane", "Monday"], extra: 312)

          expect(sentry_logs).to_not be_empty

          log_event = sentry_logs.last

          expect(log_event[:level]).to eql(level)
          expect(log_event[:body]).to eql("Hello Jane it is Monday")
          expect(log_event[:attributes][:extra]).to eql({ value: 312, type: "integer" })
          expect(log_event[:attributes]["sentry.message.template"]).to eql({ value: "Hello %s it is %s", type: "string" })
          expect(log_event[:attributes]["sentry.message.parameters.0"]).to eql({ value: "Jane", type: "string" })
          expect(log_event[:attributes]["sentry.message.parameters.1"]).to eql({ value: "Monday", type: "string" })
        end

        it "logs with hash-based template parameters" do
          Sentry.logger.public_send(level, "Hello %{name}, it is %{day}", name: "Jane", day: "Monday")

          expect(sentry_logs).to_not be_empty

          log_event = sentry_logs.last

          expect(log_event[:level]).to eql(level)
          expect(log_event[:body]).to eql("Hello Jane, it is Monday")
          expect(log_event[:attributes]["sentry.message.template"]).to eql({ value: "Hello %{name}, it is %{day}", type: "string" })
          expect(log_event[:attributes]["sentry.message.parameters.name"]).to eql({ value: "Jane", type: "string" })
          expect(log_event[:attributes]["sentry.message.parameters.day"]).to eql({ value: "Monday", type: "string" })
        end

        it "logs with hash-based template parameters and extra attributes" do
          Sentry.logger.public_send(level, "Hello %{name}, it is %{day}", name: "Jane", day: "Monday", user_id: 123)

          expect(sentry_logs).to_not be_empty

          log_event = sentry_logs.last

          expect(log_event[:level]).to eql(level)
          expect(log_event[:body]).to eql("Hello Jane, it is Monday")
          expect(log_event[:attributes][:user_id]).to eql({ value: 123, type: "integer" })
          expect(log_event[:attributes]["sentry.message.template"]).to eql({ value: "Hello %{name}, it is %{day}", type: "string" })
          expect(log_event[:attributes]["sentry.message.parameters.name"]).to eql({ value: "Jane", type: "string" })
          expect(log_event[:attributes]["sentry.message.parameters.day"]).to eql({ value: "Monday", type: "string" })
        end
      end
    end
  end
end
