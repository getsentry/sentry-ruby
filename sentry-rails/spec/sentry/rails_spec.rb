require "spec_helper"

RSpec.describe Sentry::Rails, type: :request do
  before(:all) do
    make_basic_app
  end

  it "has version set" do
    expect(described_class::VERSION).to be_a(String)
  end

  it "inserts middleware" do
    expect(Rails.application.middleware).to include(Sentry::Rack::CaptureException)
  end

  it "doesn't do anything on a normal route" do
    get "/"

    expect(response.status).to eq(200)
    expect(Sentry.get_current_client.transport.events.size).to eq(0)
  end

  # it "should capture exceptions in production" do
  #   get "/exception"

  #   expect(response.status).to eq(500)
  #   event = JSON.parse!(Sentry.client.transport.events.first[1])
  #   expect(event["exception"]["values"][0]["type"]).to eq("RuntimeError")
  #   expect(event["exception"]["values"][0]["value"]).to eq("An unhandled exception!")
  # end

  # it "should capture exceptions in production" do
  #   get "/exception"

  #   expect(response.status).to eq(500)
  #   event = JSON.parse!(Sentry.client.transport.events.first[1])
  #   expect(event["exception"]["values"][0]["type"]).to eq("RuntimeError")
  #   expect(event["exception"]["values"][0]["value"]).to eq("An unhandled exception!")
  # end

  # it "filters exception backtrace with with custom BacktraceCleaner" do
  #   get "/view_exception"

  #   event = JSON.parse!(Sentry.client.transport.events.first[1])
  #   traces = event.dig("exception", "values", 0, "stacktrace", "frames")
  #   expect(traces.dig(-1, "filename")).to eq("inline template")

  #   # we want to avoid something like "_inline_template__3014794444104730113_10960"
  #   expect(traces.dig(-1, "function")).to be_nil
  # end

  # it "doesn't filters exception backtrace if backtrace_cleanup_callback is overridden" do
  #   Sentry.configuration.backtrace_cleanup_callback = nil

  #   get "/view_exception"

  #   event = JSON.parse!(Sentry.client.transport.events.first[1])
  #   traces = event.dig("exception", "values", 0, "stacktrace", "frames")
  #   expect(traces.dig(-1, "filename")).to eq("inline template")
  #   expect(traces.dig(-1, "function")).not_to be_nil
  # end

  # it "sets transaction to ControllerName#method" do
  #   get "/exception"

  #   event = JSON.parse!(Sentry.client.transport.events.first[1])
  #   expect(event['transaction']).to eq("HelloController#exception")
  # end

  # it "sets Sentry.configuration.logger correctly" do
  #   expect(Sentry.configuration.logger).to eq(Rails.logger)
  # end

  # it "sets Sentry.configuration.project_root correctly" do
  #   expect(Sentry.configuration.project_root).to eq(Rails.root.to_s)
  # end

  # it "doesn't clobber a manually configured release" do
  #   expect(Sentry.configuration.release).to eq('beta')
  # end
end
