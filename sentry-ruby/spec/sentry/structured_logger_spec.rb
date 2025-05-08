# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sentry::StructuredLogger do
  context "when log events are not enabled" do
    before do
      perform_basic_setup
    end

    it "logger is not set up" do
      expect(Sentry.logger).to be_nil
    end
  end

  context "when log events are enabled" do
    before do
      perform_basic_setup do |config|
        config.max_log_events = 1
        config._experiments = { enable_logs: true }
      end
    end

    let(:logs) do
      Sentry.get_current_client.log_event_buffer.pending_events
    end

    ["info", "warn", "error", "fatal"].each do |level|
      describe "##{level}" do
        it "logs using default logger and LogEvent logger with extra attributes" do
          payload = { user_id: 123, action: "create" }

          Sentry.logger.public_send(level, "Hello World", payload)

          expect(logs).to_not be_empty

          log_event = logs.last

          expect(log_event.type).to eql("log")
          expect(log_event.level).to eql(level.to_sym)
          expect(log_event.body).to eql("Hello World")
          expect(log_event.attributes).to include(payload)
        end

        it "logs with template parameters" do
          Sentry.logger.public_send(level, "Hello %s it is %s", ["Jane", "Monday"])

          expect(logs).to_not be_empty

          log_event = logs.last
          log_hash = log_event.to_hash

          expect(log_event.type).to eql("log")
          expect(log_event.level).to eql(level.to_sym)
          expect(log_event.body).to eql("Hello %s it is %s")

          expect(log_hash[:body]).to eql("Hello Jane it is Monday")

          attributes = log_hash[:attributes]

          expect(attributes["sentry.message.template"]).to eql({ value: "Hello %s it is %s", type: "string" })
          expect(attributes["sentry.message.parameters.0"]).to eql({ value: "Jane", type: "string" })
          expect(attributes["sentry.message.parameters.1"]).to eql({ value: "Monday", type: "string" })
        end

        it "logs with template parameters and extra attributres" do
          Sentry.logger.public_send(level, "Hello %s it is %s", ["Jane", "Monday"], extra: 312)

          expect(logs).to_not be_empty

          log_event = logs.last
          log_hash = log_event.to_hash

          expect(log_event.type).to eql("log")
          expect(log_event.level).to eql(level.to_sym)
          expect(log_event.body).to eql("Hello %s it is %s")

          expect(log_hash[:body]).to eql("Hello Jane it is Monday")

          attributes = log_hash[:attributes]

          expect(attributes[:extra]).to eql({ value: 312, type: "integer" })
          expect(attributes["sentry.message.template"]).to eql({ value: "Hello %s it is %s", type: "string" })
          expect(attributes["sentry.message.parameters.0"]).to eql({ value: "Jane", type: "string" })
          expect(attributes["sentry.message.parameters.1"]).to eql({ value: "Monday", type: "string" })
        end
      end
    end
  end
end
