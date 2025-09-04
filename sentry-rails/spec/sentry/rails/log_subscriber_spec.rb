# frozen_string_literal: true

require "spec_helper"

require "sentry/rails/log_subscriber"
require "sentry/rails/log_subscribers/parameter_filter"

RSpec.describe Sentry::Rails::LogSubscriber, type: :request do
  let!(:test_subscriber) { test_subscriber_class.new }

  after do
    test_subscriber_class.detach_from(:test_component)
  end

  context "with no parameter filtering" do
    let(:test_subscriber_class) do
      Class.new(described_class) do
        attach_to :test_component

        def test_event(event)
          log_structured_event(
            message: "Test event occurred",
            attributes: {
              duration_ms: duration_ms(event),
              test_data: event.payload[:test_data],
              component: "test_component"
            }
          )
        end

        def error_test_event(event)
          log_structured_event(
            message: "Error test event",
            level: :error,
            attributes: {
              duration_ms: duration_ms(event),
              error_data: event.payload[:error_data]
            }
          )
        end
      end
    end

    before do
      make_basic_app do |config|
        config.enable_logs = true
        config.structured_logging.logger_class = Sentry::DebugStructuredLogger
      end
    end

    describe "ActiveSupport notifications integration" do
      it "responds to real ActiveSupport notifications and logs structured events" do
        ActiveSupport::Notifications.instrument("test_event.test_component", test_data: "sample_data") do
          sleep(0.01)
        end

        logged_events = Sentry.logger.logged_events
        expect(logged_events).not_to be_empty

        log_event = logged_events.find { |event| event["message"] == "Test event occurred" }
        expect(log_event).not_to be_nil
        expect(log_event["level"]).to eq("info")
        expect(log_event["message"]).to eq("Test event occurred")
        expect(log_event["attributes"]["test_data"]).to eq("sample_data")
        expect(log_event["attributes"]["component"]).to eq("test_component")
        expect(log_event["attributes"]["duration_ms"]).to be_a(Float)
        expect(log_event["attributes"]["duration_ms"]).to be > 0
        expect(log_event["timestamp"]).to be_a(String)
      end

      it "uses appropriate log level based on duration thresholds" do
        ActiveSupport::Notifications.instrument("test_event.test_component", test_data: "fast") do
          sleep(0.1)
        end

        logged_events = Sentry.logger.logged_events
        expect(logged_events.size).to eq(1)

        log_event = logged_events.first
        expect(log_event["level"]).to eq("info")
        expect(log_event["attributes"]["test_data"]).to eq("fast")
        expect(log_event["attributes"]["duration_ms"]).to be > 50
      end

      it "handles events with various payload data types" do
        test_payloads = [
          { test_data: "string_value" },
          { test_data: { nested: "hash" } },
          { test_data: [1, 2, 3] },
          { test_data: nil }
        ]

        expected_values = [
          "string_value",
          { "nested" => "hash" },
          [1, 2, 3],
          nil
        ]

        test_payloads.each do |payload|
          ActiveSupport::Notifications.instrument("test_event.test_component", payload) do
            sleep 0.01
          end
        end

        logged_events = Sentry.logger.logged_events
        expect(logged_events.size).to eq(test_payloads.size)

        logged_events.each_with_index do |log_event, index|
          expect(log_event["message"]).to eq("Test event occurred")
          expect(log_event["attributes"]["test_data"]).to eq(expected_values[index])
          expect(log_event["level"]).to eq("info")
        end
      end

      it "calculates duration correctly from real events" do
        ActiveSupport::Notifications.instrument("test_event.test_component", test_data: "duration_test") do
          sleep(0.05) # 50ms
        end

        logged_events = Sentry.logger.logged_events
        log_event = logged_events.first
        duration = log_event["attributes"]["duration_ms"]

        expect(duration).to be_a(Float)
        expect(duration).to be >= 40.0
        expect(duration).to be < 100.0
        expect(duration.round(2)).to eq(duration)
      end
    end

    describe "error handling" do
      it "handles logging errors gracefully and logs to sdk_logger" do
        failing_logger = double("failing_logger")

        allow(failing_logger).to receive(:error).and_raise(StandardError.new("Logging failed"))
        allow(Sentry).to receive(:logger).and_return(failing_logger)

        sdk_logger_output = StringIO.new
        Sentry.configuration.sdk_logger = ::Logger.new(sdk_logger_output)

        expect {
          ActiveSupport::Notifications.instrument("error_test_event.test_component", error_data: "error_test") do
            sleep 0.01
          end
        }.not_to raise_error

        sdk_output = sdk_logger_output.string
        expect(sdk_output).to include("Failed to log structured event: Logging failed")
      end
    end

    describe "Rails version compatibility" do
      context "when Rails version is less than 6.0", skip: Rails.version.to_f >= 6.0 ? "Rails 6.0+" : false do
        it "provides custom detach_from implementation" do
          temp_subscriber_class = Class.new(described_class) do
            attach_to :temp_test

            def temp_event(event)
              log_structured_event(message: "Temp event", attributes: { data: event.payload[:data] })
            end
          end

          ActiveSupport::Notifications.instrument("temp_event.temp_test", data: "before_detach") do
            sleep 0.01
          end

          initial_log_count = Sentry.logger.logged_events.size
          expect(initial_log_count).to be > 0

          temp_subscriber_class.detach_from(:temp_test)

          Sentry.logger.clear

          ActiveSupport::Notifications.instrument("temp_event.temp_test", data: "after_detach") do
            sleep 0.01
          end

          expect(Sentry.logger.logged_events).to be_empty
        end
      end

      context "when Rails version is 6.0 or higher", skip: Rails.version.to_f < 6.0 ? "Rails 5.x" : false do
        it "uses Rails built-in detach_from method" do
          expect(described_class).to respond_to(:detach_from)

          temp_subscriber_class = Class.new(described_class) do
            attach_to :temp_test_rails6

            def temp_event(event)
              log_structured_event(message: "Temp event Rails 6+", attributes: { data: event.payload[:data] })
            end
          end

          ActiveSupport::Notifications.instrument("temp_event.temp_test_rails6", data: "test") do
            sleep 0.01
          end

          initial_log_count = Sentry.logger.logged_events.size
          expect(initial_log_count).to be > 0

          temp_subscriber_class.detach_from(:temp_test_rails6)

          Sentry.logger.clear

          ActiveSupport::Notifications.instrument("temp_event.temp_test_rails6", data: "after_detach") do
            sleep 0.01
          end

          expect(Sentry.logger.logged_events).to be_empty
        end
      end
    end
  end

  context "parameter filtering integration" do
    let(:test_subscriber_class) do
      Class.new(described_class) do
        include Sentry::Rails::LogSubscribers::ParameterFilter

        attach_to :filtering_test

        def filtering_event(event)
          attributes = {
            duration_ms: duration_ms(event),
            component: "filtering_test"
          }

          if Sentry.configuration.send_default_pii && event.payload[:params]
            filtered_params = filter_sensitive_params(event.payload[:params])
            attributes[:params] = filtered_params unless filtered_params.empty?
          end

          log_structured_event(
            message: "Filtering event occurred",
            attributes: attributes
          )
        end
      end
    end

    before do
      make_basic_app do |config, app|
        config.enable_logs = true
        config.structured_logging.logger_class = Sentry::DebugStructuredLogger
        config.send_default_pii = true
      end
    end

    it_behaves_like "parameter filtering" do
      let(:test_instance) { test_subscriber }
    end
  end
end
