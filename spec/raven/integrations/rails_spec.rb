require "spec_helper"
require "rspec/rails"
require "raven/transports/dummy"

describe TestApp, :type => :request do
  before(:all) do
    Raven.configure do |config|
      config.dsn = 'dummy://notaserver'
      config.encoding = 'json'
    end

    TestApp.initialize!
  end

  it "inserts middleware" do
    expect(TestApp.middleware).to include(Raven::Rack)
  end

  pending "should capture exceptions" do
    get "/exception"
    expect(response.status).to eq(500)
    expect(Raven.client.transport.events.size).to eq(1)
  end
end
