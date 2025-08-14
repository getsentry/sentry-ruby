# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sentry::Rails::LogSubscriber do
  let(:test_subscriber_class) do
    Class.new(described_class) do
      def test_event(event)
        return if excluded_event?(event)

        duration = duration_ms(event)

        log_structured_event(
          message: "Test event processed",
          level: :info,
          attributes: {
            event_name: event.name,
            duration_ms: duration,
            payload_data: event.payload[:data]
          }
        )
      end

      def custom_event(event)
        return if excluded_event?(event)

        log_structured_event(
          message: "Custom event: #{event.payload[:action]}",
          level: :info,
          attributes: {
            action: event.payload[:action],
            user_id: event.payload[:user_id],
            metadata: event.payload[:metadata]
          }
        )
      end
    end
  end

  before do
    make_basic_app do |config|
      config.enable_logs = true
    end
  end

  describe "integration with ActiveSupport::Notifications" do
    let(:subscriber) { test_subscriber_class.new }

    before do
      test_subscriber_class.attach_to :test_component
    end

    after do
      test_subscriber_class.detach_from :test_component
    end

    it "logs events when notifications are published" do
      ActiveSupport::Notifications.instrument("test_event.test_component", data: "test_data") do
        sleep(0.01)
      end

      Sentry.get_current_client.log_event_buffer.flush

      expect(sentry_logs).not_to be_empty

      log_event = sentry_logs.find { |log| log[:body] == "Test event processed" }
      expect(log_event).not_to be_nil
      expect(log_event[:level]).to eq("info")
      expect(log_event[:attributes][:event_name]).to eq({ value: "test_event.test_component", type: "string" })
      expect(log_event[:attributes][:duration_ms][:value]).to be > 0
      expect(log_event[:attributes][:payload_data]).to eq({ value: "test_data", type: "string" })
    end

    it "logs custom events with different attributes" do
      ActiveSupport::Notifications.instrument("custom_event.test_component",
        action: "user_login",
        user_id: 123,
        metadata: { ip: "192.168.1.1" }
      )

      Sentry.get_current_client.log_event_buffer.flush

      expect(sentry_logs).not_to be_empty

      log_event = sentry_logs.find { |log| log[:body] == "Custom event: user_login" }
      expect(log_event).not_to be_nil
      expect(log_event[:level]).to eq("info")
      expect(log_event[:attributes][:action]).to eq({ value: "user_login", type: "string" })
      expect(log_event[:attributes][:user_id]).to eq({ value: 123, type: "integer" })
      expect(log_event[:attributes][:metadata][:value]).to eq({ ip: "192.168.1.1" })
    end

    it "excludes events starting with !" do
      ActiveSupport::Notifications.instrument("!excluded_event.test_component", data: "should_not_log")

      Sentry.get_current_client.log_event_buffer.flush

      excluded_logs = sentry_logs.select { |log| log[:body]&.include?("should_not_log") }
      expect(excluded_logs).to be_empty
    end
  end

  describe "attach_to behavior" do
    it "sets logger to nil to prevent standard Rails logging" do
      subscriber_class = Class.new(described_class)
      subscriber_class.attach_to :test_component

      expect(subscriber_class.logger).to be_nil
    end
  end

  describe "when logging is disabled" do
    before do
      make_basic_app do |config|
        config.enable_logs = false
      end
    end

    let(:subscriber) { test_subscriber_class.new }

    before do
      test_subscriber_class.attach_to :test_component
    end

    after do
      test_subscriber_class.detach_from :test_component
    end

    it "does not log events when logging is disabled" do
      initial_log_count = sentry_logs.count

      ActiveSupport::Notifications.instrument("test_event.test_component", data: "test_data")

      if Sentry.get_current_client&.log_event_buffer
        Sentry.get_current_client.log_event_buffer.flush
      end

      expect(sentry_logs.count).to eq(initial_log_count)
    end
  end
end
