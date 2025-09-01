# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sentry::Rails::StructuredLogging, type: :request do
  context "when sentry structured logging is disabled" do
    before do
      make_basic_app do |config|
        config.enable_logs = false
        config.rails.structured_logging.enabled = true
      end
    end

    it "does not capture structured logs" do
      get "/posts"

      Post.first

      Sentry.get_current_client.flush

      expect(sentry_logs).to be_empty
    end
  end

  context "when rails structured logging is disabled" do
    before do
      make_basic_app do |config|
        config.enable_logs = true
        config.rails.structured_logging.enabled = false
      end
    end

    it "does not capture structured logs" do
      get "/posts"

      Post.first

      Sentry.get_current_client.flush

      expect(sentry_logs).to be_empty
    end
  end
end
