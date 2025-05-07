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

    # TODO: At the moment the Sentry::Logger enforces info - is that intentional?
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
      end
    end
  end
end
