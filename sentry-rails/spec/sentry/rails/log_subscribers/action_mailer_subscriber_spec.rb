# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sentry::Rails::LogSubscribers::ActionMailerSubscriber do
  context "when logging is enabled" do
    before do
      make_basic_app do |config|
        config.enable_logs = true

        config.rails.structured_logging.enabled = true
        config.rails.structured_logging.subscribers = { action_mailer: Sentry::Rails::LogSubscribers::ActionMailerSubscriber }
      end
    end
    describe "integration with ActiveSupport::Notifications" do
      it "logs deliver events when emails are sent" do
        sentry_transport.events.clear
        sentry_transport.envelopes.clear

        ActiveSupport::Notifications.instrument("deliver.action_mailer",
          mailer: "UserMailer",
          perform_deliveries: true,
          delivery_method: :test,
          date: Time.current,
          message_id: "test@example.com"
        ) do
          sleep(0.01)
        end

        Sentry.get_current_client.flush

        expect(sentry_logs).not_to be_empty

        log_event = sentry_logs.find { |log| log[:body] == "Email delivered via UserMailer" }
        expect(log_event).not_to be_nil
        expect(log_event[:level]).to eq("info")
        expect(log_event[:attributes][:mailer][:value]).to eq("UserMailer")
        expect(log_event[:attributes][:duration_ms][:value]).to be > 0
        expect(log_event[:attributes][:perform_deliveries][:value]).to be true
        expect(log_event[:attributes][:delivery_method][:value]).to eq("\"test\"")
        expect(log_event[:attributes]["sentry.origin"][:value]).to eq("auto.log.rails.log_subscriber")
        expect(log_event[:attributes][:date]).to be_present
      end

      it "logs process events when mailer actions are processed" do
        ActiveSupport::Notifications.instrument("process.action_mailer",
          mailer: "UserMailer",
          action: "welcome_email",
          params: { user_id: 123, name: "John Doe" }
        ) do
          sleep(0.01)
        end

        Sentry.get_current_client.flush

        expect(sentry_logs).not_to be_empty

        log_event = sentry_logs.find { |log| log[:body] == "UserMailer#welcome_email" }
        expect(log_event).not_to be_nil
        expect(log_event[:level]).to eq("info")
        expect(log_event[:attributes][:mailer][:value]).to eq("UserMailer")
        expect(log_event[:attributes][:action][:value]).to eq("welcome_email")
        expect(log_event[:attributes][:duration_ms][:value]).to be > 0
      end

      it "includes delivery method when available" do
        ActiveSupport::Notifications.instrument("deliver.action_mailer",
          mailer: "NotificationMailer",
          perform_deliveries: true,
          delivery_method: :smtp
        )

        Sentry.get_current_client.flush

        expect(sentry_logs).not_to be_empty

        log_event = sentry_logs.find { |log| log[:body] == "Email delivered via NotificationMailer" }
        expect(log_event).not_to be_nil
        expect(log_event[:attributes][:delivery_method][:value]).to eq("\"smtp\"")
      end

      it "includes date when available" do
        test_date = Time.current
        ActiveSupport::Notifications.instrument("deliver.action_mailer",
          mailer: "NotificationMailer",
          perform_deliveries: true,
          date: test_date
        )

        Sentry.get_current_client.flush

        expect(sentry_logs).not_to be_empty

        log_event = sentry_logs.find { |log| log[:body] == "Email delivered via NotificationMailer" }
        expect(log_event).not_to be_nil
        expect(log_event[:attributes][:date][:value]).to eq(test_date.to_s)
      end

      it "handles missing optional fields gracefully" do
        ActiveSupport::Notifications.instrument("deliver.action_mailer",
          mailer: "MinimalMailer",
          perform_deliveries: false
        )

        Sentry.get_current_client.flush

        expect(sentry_logs).not_to be_empty

        log_event = sentry_logs.find { |log| log[:body] == "Email delivered via MinimalMailer" }
        expect(log_event).not_to be_nil
        expect(log_event[:attributes][:mailer][:value]).to eq("MinimalMailer")
        expect(log_event[:attributes][:perform_deliveries][:value]).to be false
        expect(log_event[:attributes]).not_to have_key(:delivery_method)
        expect(log_event[:attributes]).not_to have_key(:date)
        expect(log_event[:attributes]).not_to have_key(:message_id)
      end

      it "handles process events with missing params gracefully" do
        ActiveSupport::Notifications.instrument("process.action_mailer",
          mailer: "UserMailer",
          action: "welcome_email"
        )

        Sentry.get_current_client.flush

        expect(sentry_logs).not_to be_empty

        log_event = sentry_logs.find { |log| log[:body] == "UserMailer#welcome_email" }
        expect(log_event).not_to be_nil
        expect(log_event[:attributes][:mailer][:value]).to eq("UserMailer")
        expect(log_event[:attributes][:action][:value]).to eq("welcome_email")
        expect(log_event[:attributes]).not_to have_key(:params)
      end

      context "when send_default_pii is enabled" do
        before do
          Sentry.configuration.send_default_pii = true
        end

        after do
          Sentry.configuration.send_default_pii = false
        end

        it "includes message_id for deliver events" do
          ActiveSupport::Notifications.instrument("deliver.action_mailer",
            mailer: "UserMailer",
            perform_deliveries: true,
            message_id: "unique-message-id@example.com"
          )

          Sentry.get_current_client.flush

          expect(sentry_logs).not_to be_empty

          log_event = sentry_logs.find { |log| log[:body] == "Email delivered via UserMailer" }
          expect(log_event).not_to be_nil
          expect(log_event[:attributes][:message_id][:value]).to eq("unique-message-id@example.com")
        end

        it "includes filtered parameters for process events" do
          ActiveSupport::Notifications.instrument("process.action_mailer",
            mailer: "UserMailer",
            action: "welcome_email",
            params: {
              user_id: 123,
              safe_param: "value",
              password: "secret",
              email_address: "user@example.com",
              subject: "Welcome!",
              api_key: "secret-key"
            }
          )

          Sentry.get_current_client.flush

          expect(sentry_logs).not_to be_empty

          log_event = sentry_logs.find { |log| log[:body] == "UserMailer#welcome_email" }
          expect(log_event).not_to be_nil
          expect(log_event[:attributes][:params]).to be_present

          params = JSON.parse(log_event[:attributes][:params][:value])

          expect(params).to include("user_id" => 123, "safe_param" => "value")
          expect(params["password"]).to eq("[FILTERED]")
          expect(params["api_key"]).to eq("[FILTERED]")
          expect(params).to include("email_address" => "user@example.com", "subject" => "Welcome!")
        end
      end

      context "when send_default_pii is disabled" do
        it "does not include message_id for deliver events" do
          ActiveSupport::Notifications.instrument("deliver.action_mailer",
            mailer: "UserMailer",
            perform_deliveries: true,
            message_id: "unique-message-id@example.com"
          )

          Sentry.get_current_client.flush

          expect(sentry_logs).not_to be_empty

          log_event = sentry_logs.find { |log| log[:body] == "Email delivered via UserMailer" }
          expect(log_event).not_to be_nil
          expect(log_event[:attributes]).not_to have_key(:message_id)
        end

        it "does not include parameters for process events" do
          sentry_transport.events.clear
          sentry_transport.envelopes.clear

          ActiveSupport::Notifications.instrument("process.action_mailer",
            mailer: "UserMailer",
            action: "welcome_email",
            params: { user_id: 123, name: "John Doe" }
          )

          Sentry.get_current_client.flush

          expect(sentry_logs).not_to be_empty

          log_event = sentry_logs.find { |log| log[:body] == "UserMailer#welcome_email" }
          expect(log_event).not_to be_nil
          expect(log_event[:attributes]).not_to have_key(:params)
        end
      end
    end
  end

  context "when logging is disabled" do
    before do
      make_basic_app do |config|
        config.enable_logs = false

        config.rails.structured_logging.enabled = true
        config.rails.structured_logging.subscribers = { action_mailer: Sentry::Rails::LogSubscribers::ActionMailerSubscriber }
      end
    end

    it "does not log events when logging is disabled" do
      initial_log_count = sentry_logs.count

      ActiveSupport::Notifications.instrument("deliver.action_mailer",
        mailer: "UserMailer",
        perform_deliveries: true
      )

      Sentry.get_current_client.flush

      expect(sentry_logs.count).to eq(initial_log_count)
    end
  end

  include_examples "parameter filtering", described_class
end
