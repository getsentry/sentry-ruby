# frozen_string_literal: true

RSpec.describe "Structured Logging", type: :e2e do
  it "captures Rails application logs using structured logging" do
    response = make_request("/posts")
    expect(response.code).to eq("200")

    logged_events = Sentry.logger.logged_events
    expect(logged_events).not_to be_empty

    log_event = logged_events.first
    expect(log_event).to have_key("timestamp")
    expect(log_event).to have_key("level")
    expect(log_event).to have_key("message")
    expect(log_event).to have_key("attributes")
    expect(log_event["timestamp"]).to be_a(String)
  end

  it "captures logs from Rails mini app" do
    response = make_request("/posts")
    expect(response.code).to eq("200")

    logged_events = Sentry.logger.logged_events
    expect(logged_events).not_to be_empty

    posts_log = logged_events.find { |log| log["message"] == "Posts index accessed" }
    expect(posts_log).not_to be_nil
    expect(posts_log["level"]).to eq("info")
    expect(posts_log["attributes"]["posts_count"]).to eq(2)
  end

  it "captures structured logs with proper format" do
    response = make_request("/posts")
    expect(response.code).to eq("200")

    logged_events = Sentry.logger.logged_events
    expect(logged_events).not_to be_empty

    log_event = logged_events.first
    expect(log_event).to have_key("timestamp")
    expect(log_event).to have_key("level")
    expect(log_event).to have_key("message")
    expect(log_event).to have_key("attributes")
    expect(log_event["timestamp"]).to be_a(String)
    expect(log_event["level"]).to be_a(String)
    expect(log_event["message"]).to be_a(String)
    expect(log_event["attributes"]).to be_a(Hash)
  end
end
