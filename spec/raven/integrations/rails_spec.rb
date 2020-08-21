require "spec_helper"

RSpec.describe "Rails Integration", :type => :request, :rails => true do
  before(:all) do
    TestApp.initialize!
  end

  after(:each) do
    Raven.client.transport.events = []
  end

  it "inserts middleware" do
    expect(TestApp.middleware).to include(Raven::Rack)
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

  it "should properly set the exception's URL" do
    get "/exception"

    event = JSON.parse!(Raven.client.transport.events.first[1])
    expect(event['request']['url']).to eq("http://www.example.com/exception")
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
