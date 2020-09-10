require "spec_helper"

RSpec.describe "Raven::Breadcrumbs::ActiveSupportLogger", :type => :request, :rails => true do
  before(:all) do
    Raven.configuration.breadcrumbs_logger = [:active_support_logger]
    Rails.application = make_basic_app
  end

  after(:all) do
    Raven.configuration.breadcrumbs_logger = []
    Raven::Breadcrumbs::ActiveSupportLogger.detach
    # even though we cleanup breadcrumbs in the rack middleware
    # Breadcrumbs::ActiveSupportLogger subscribes to "every" instrumentation
    # so it'll create other instrumentations "after" the request is finished
    # and we should clear those as well
    Raven::BreadcrumbBuffer.clear!
  end

  it "captures correct data" do
    get "/exception"

    expect(response.status).to eq(500)
    event = JSON.parse!(Raven.client.transport.events.first[1])
    breadcrumbs = event.dig("breadcrumbs", "values")
    expect(breadcrumbs.count).to eq(2)

    if Rails.version.to_i >= 5
      expect(breadcrumbs.first["data"]).to match(
        {
          "controller" => "HelloController",
          "action" => "exception",
          "params" => { "controller" => "hello", "action" => "exception" },
          "headers" => anything,
          "format" => "html",
          "method" => "GET",
          "path" => "/exception"
        }
      )
    else
      expect(breadcrumbs.first["data"]).to match(
        {
          "controller" => "HelloController",
          "action" => "exception",
          "params" => { "controller" => "hello", "action" => "exception" },
          "format" => "html",
          "method" => "GET",
          "path" => "/exception"
        }
      )

    end
  end
end
