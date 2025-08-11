# frozen_string_literal: true

require 'net/http'
require 'uri'

RSpec.describe "Structured Logging", type: :feature do
  include Test::Helper

  let(:rails_app_url) { "http://localhost:4000" }

  let(:debug_logger) do
    config = Sentry::Configuration.new
    Sentry::DebugStructuredLogger.new(config)
  end

  def logged_structured_events
    debug_logger.logged_events
  end

  def clear_structured_logs
    debug_logger.clear
  end

  def make_request(path)
    uri = URI("#{rails_app_url}#{path}")
    Net::HTTP.get_response(uri)
  end

  before(:each) do
    clear_structured_logs
  end

  it "captures Rails application logs using DebugStructuredLogger" do
    response = make_request("/posts")
    expect(response.code).to eq("200")

    sleep(1)

    logged_events = logged_structured_events
    expect(logged_events).not_to be_empty

    expect(logged_events.length).to be > 0

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

    sleep(1)

    logged_events = logged_structured_events

    expect(logged_events).not_to be_empty

    posts_log = logged_events.find { |log| log["message"] == "Posts index accessed" }
    expect(posts_log).not_to be_nil
    expect(posts_log["level"]).to eq("info")
    expect(posts_log["attributes"]["posts_count"]).to eq(2)
  end

  it "captures structured logs with proper format" do
    response = make_request("/posts")
    expect(response.code).to eq("200")

    sleep(1)

    logged_events = logged_structured_events
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

  it "verifies Rails mini app is configured with DebugStructuredLogger" do
    response = make_request("/health")
    expect(response.code).to eq("200")

    health_data = JSON.parse(response.body)
    expect(health_data["sentry_initialized"]).to be true
    expect(health_data["structured_log_file_writable"]).to be true

    make_request("/posts")

    sleep(1)

    logged_events = logged_structured_events
    expect(logged_events).not_to be_empty

    log_event = logged_events.first
    expect(log_event).to include("timestamp", "level", "message", "attributes")
  end
end
