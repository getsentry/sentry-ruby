# frozen_string_literal: true

require "spec_helper"
require "sentry/rails/log_subscribers/action_controller_subscriber"

RSpec.describe Sentry::Rails::LogSubscribers::ActionControllerSubscriber, type: :request do
  before do
    make_basic_app do |config, app|
      config.enable_logs = true
      config.rails.structured_logging.enabled = true
      config.rails.structured_logging.attach_to = [:action_controller]
      app.config.filter_parameters += [:api_key, :credit_card, :authorization]
    end
  end

  describe "integration with ActiveSupport::Notifications" do
    it "logs controller action events when requests are processed" do
      get "/world"

      Sentry.get_current_client.flush

      expect(sentry_logs).not_to be_empty

      log_event = sentry_logs.find { |log| log[:body] == "HelloController#world" }
      expect(log_event).not_to be_nil
      expect(log_event[:level]).to eq("info")
      expect(log_event[:attributes][:controller][:value]).to eq("HelloController")
      expect(log_event[:attributes][:action][:value]).to eq("world")
      expect(log_event[:attributes][:status][:value]).to eq(200)
      expect(log_event[:attributes][:duration_ms][:value]).to be > 0
      expect(log_event[:attributes][:method][:value]).to eq("GET")
      expect(log_event[:attributes][:path][:value]).to eq("/world")
      expect(log_event[:attributes][:format][:value]).to eq(:html)
    end

    it "logs bad requests appropriately" do
      get "/not_found"

      Sentry.get_current_client.flush

      expect(sentry_logs).not_to be_empty

      log_event = sentry_logs.find { |log| log[:body] == "HelloController#not_found" }
      expect(log_event).not_to be_nil
      expect(log_event[:level].to_sym).to be(:warn)
      expect(log_event[:attributes][:status][:value]).to eq(400)
    end

    it "logs error status codes with error level" do
      get "/exception"

      Sentry.get_current_client.flush

      expect(sentry_logs).not_to be_empty

      log_event = sentry_logs.find { |log| log[:body] == "HelloController#exception" }
      expect(log_event).not_to be_nil
      expect(log_event[:level]).to eq("error")
      expect(log_event[:attributes][:status][:value]).to eq(500)
    end

    it "includes view runtime when available" do
      get "/view"

      Sentry.get_current_client.flush

      expect(sentry_logs).not_to be_empty

      log_event = sentry_logs.find { |log| log[:body] == "HelloController#view" }
      expect(log_event).not_to be_nil
      expect(log_event[:attributes][:view_runtime_ms]).to be_present
      expect(log_event[:attributes][:view_runtime_ms][:value]).to be >= 0
    end

    it "includes database runtime when available" do
      Post.create!
      get "/posts"

      Sentry.get_current_client.flush

      expect(sentry_logs).not_to be_empty

      log_event = sentry_logs.find { |log| log[:body] == "PostsController#index" }
      expect(log_event).not_to be_nil

      if Rails.version.to_f >= 6.0
        expect(log_event[:attributes][:db_runtime_ms]).to be_present
        expect(log_event[:attributes][:db_runtime_ms][:value]).to be >= 0
      else
        if log_event[:attributes][:db_runtime_ms]
          expect(log_event[:attributes][:db_runtime_ms][:value]).to be >= 0
        end
      end
    end

    context "when send_default_pii is enabled" do
      before do
        Sentry.configuration.send_default_pii = true
      end

      after do
        Sentry.configuration.send_default_pii = false
      end

      it "includes filtered request parameters" do
        get "/world", params: { safe_param: "value", password: "secret" }

        Sentry.get_current_client.flush

        expect(sentry_logs).not_to be_empty

        log_event = sentry_logs.find { |log| log[:body] == "HelloController#world" }
        expect(log_event).not_to be_nil
        expect(log_event[:attributes][:params]).to be_present
        expect(log_event[:attributes][:params][:value]).to include("safe_param" => "value")
        expect(log_event[:attributes][:params][:value]).to include("password" => "[FILTERED]")
      end

      it "filters sensitive parameter names" do
        get "/world", params: {
          normal_param: "value",
          password: "secret",
          api_key: "key123",
          credit_card: "1234567890",
          authorization: "Bearer token"
        }

        Sentry.get_current_client.flush

        expect(sentry_logs).not_to be_empty

        log_event = sentry_logs.find { |log| log[:body] == "HelloController#world" }
        expect(log_event).not_to be_nil

        params = log_event[:attributes][:params][:value]
        expect(params).to include("normal_param" => "value")
        expect(params).to include("password" => "[FILTERED]")
        expect(params).to include("api_key" => "[FILTERED]")
        expect(params).to include("credit_card" => "[FILTERED]")
        expect(params).to include("authorization" => "[FILTERED]")
      end

      it "respects Rails filter_parameters configuration" do
        original_filter_params = Rails.application.config.filter_parameters.dup
        Rails.application.config.filter_parameters += [:custom_secret]

        get "/world", params: {
          normal_param: "value",
          custom_secret: "should_be_filtered",
          another_param: "visible"
        }

        Sentry.get_current_client.flush

        expect(sentry_logs).not_to be_empty

        log_event = sentry_logs.find { |log| log[:body] == "HelloController#world" }
        expect(log_event).not_to be_nil

        params = log_event[:attributes][:params][:value]
        expect(params).to include("normal_param" => "value")
        expect(params).to include("another_param" => "visible")
        expect(params).to include("custom_secret" => "[FILTERED]")

        Rails.application.config.filter_parameters = original_filter_params
      end

      it "handles nested parameters correctly" do
        get "/world", params: {
          user: {
            name: "John",
            password: "secret123",
            profile: {
              api_key: "key456",
              public_info: "visible"
            }
          },
          normal_param: "value"
        }

        Sentry.get_current_client.flush

        expect(sentry_logs).not_to be_empty

        log_event = sentry_logs.find { |log| log[:body] == "HelloController#world" }
        expect(log_event).not_to be_nil

        params = log_event[:attributes][:params][:value]
        expect(params).to include("normal_param" => "value")
        expect(params["user"]).to include("name" => "John")
        expect(params["user"]).to include("password" => "[FILTERED]")
        expect(params["user"]["profile"]).to include("api_key" => "[FILTERED]")
        expect(params["user"]["profile"]).to include("public_info" => "visible")
      end
    end

    context "when send_default_pii is disabled" do
      it "does not include request parameters" do
        sentry_transport.events.clear
        sentry_transport.envelopes.clear

        get "/world", params: { param: "value" }

        Sentry.get_current_client.flush

        expect(sentry_logs).not_to be_empty

        log_event = sentry_logs.find { |log| log[:body] == "HelloController#world" }
        expect(log_event).not_to be_nil
        expect(log_event[:attributes]).not_to have_key(:params)
      end
    end
  end

  describe "when logging is disabled" do
    before do
      make_basic_app do |config|
        config.enable_logs = false
        config.rails.structured_logging.enabled = true
        config.rails.structured_logging.attach_to = [:action_controller]
      end
    end

    it "does not log events when logging is disabled" do
      initial_log_count = sentry_logs.count

      get "/world"

      if Sentry.get_current_client&.log_event_buffer
        Sentry.get_current_client.flush
      end

      expect(sentry_logs.count).to eq(initial_log_count)
    end
  end

  describe "ParameterFilter functionality" do
    include_examples "parameter filtering", described_class
  end
end
