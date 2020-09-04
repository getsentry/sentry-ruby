require "spec_helper"

RSpec.describe "Rails Integration", :type => :request, :rails => true do
  before(:all) do
    make_basic_app
  end

  after(:each) do
    Raven.client.transport.events = []
  end

  it "inserts middleware" do
    expect(Rails.application.middleware).to include(Raven::Rack)
  end

  it "doesn't do anything on a normal route" do
    get "/"

    expect(response.status).to eq(200)
    expect(Raven.client.transport.events.size).to eq(0)
  end

  it "should capture exceptions in production" do
    get "/exception"

    expect(response.status).to eq(500)
    event = JSON.parse!(Raven.client.transport.events.first[1])
    expect(event["exception"]["values"][0]["type"]).to eq("RuntimeError")
    expect(event["exception"]["values"][0]["value"]).to eq("An unhandled exception!")
  end

  it "should capture exceptions in production" do
    get "/exception"

    expect(response.status).to eq(500)
    event = JSON.parse!(Raven.client.transport.events.first[1])
    expect(event["exception"]["values"][0]["type"]).to eq("RuntimeError")
    expect(event["exception"]["values"][0]["value"]).to eq("An unhandled exception!")
  end

  it "filters exception backtrace with with custom BacktraceCleaner" do
    get "/view_exception"

    event = JSON.parse!(Raven.client.transport.events.first[1])
    traces = event.dig("exception", "values", 0, "stacktrace", "frames")
    expect(traces.dig(-1, "filename")).to eq("inline template")

    # we want to avoid something like "_inline_template__3014794444104730113_10960"
    expect(traces.dig(-1, "function")).to be_nil
  end

  it "doesn't filters exception backtrace if backtrace_cleanup_callback is overridden" do
    Raven.configuration.backtrace_cleanup_callback = nil

    get "/view_exception"

    event = JSON.parse!(Raven.client.transport.events.first[1])
    traces = event.dig("exception", "values", 0, "stacktrace", "frames")
    expect(traces.dig(-1, "filename")).to eq("inline template")
    expect(traces.dig(-1, "function")).not_to be_nil
  end

  it "sets transaction to ControllerName#method" do
    get "/exception"

    event = JSON.parse!(Raven.client.transport.events.first[1])
    expect(event['transaction']).to eq("HelloController#exception")
  end

  it "sets Raven.configuration.logger correctly" do
    expect(Raven.configuration.logger).to eq(Rails.logger)
  end

  it "sets Raven.configuration.project_root correctly" do
    expect(Raven.configuration.project_root).to eq(Rails.root.to_s)
  end

  it "doesn't clobber a manually configured release" do
    expect(Raven.configuration.release).to eq('beta')
  end
end
