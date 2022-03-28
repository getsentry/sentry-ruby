require 'rails_helper'

RSpec.describe "Welcomes", type: :request do
  before do
    setup_sentry_test
  end

  after do
    teardown_sentry_test
  end

  describe "GET /" do
    it "captures and sends exception to Sentry" do
      get "/"
      expect(response).to have_http_status(500)
      expect(sentry_events.count).to eq(2)

      error_event = sentry_events.first
      expect(error_event.transaction).to eq("WelcomeController#index")
      error = extract_sentry_exceptions(error_event).first
      expect(error.type).to eq("ZeroDivisionError")
      expect(error_event.tags).to match(counter: 1, request_id: anything)

      transaction_event = sentry_events.last
      expect(transaction_event.spans.count).to eq(3)
    end
  end

  describe "GET /view_error" do
    it "captures and sends exception to Sentry" do
      get "/view_error"
      expect(response).to have_http_status(500)
      expect(sentry_events.count).to eq(2)

      error_event = sentry_events.first
      expect(error_event.transaction).to eq("WelcomeController#view_error")
      error = extract_sentry_exceptions(error_event).first
      expect(error.type).to eq("NameError")
      expect(error_event.tags).to match(counter: 1, request_id: anything)

      transaction_event = sentry_events.last
      expect(transaction_event.spans.count).to eq(4)
    end
  end
end
