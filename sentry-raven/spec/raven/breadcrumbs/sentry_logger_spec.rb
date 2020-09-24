require "spec_helper"

RSpec.describe "Raven::Breadcrumbs::SentryLogger", :type => :request, :rails => true do
  before(:all) do
    Raven.configuration.breadcrumbs_logger = [:sentry_logger]
    Rails.application = make_basic_app
  end

  after(:all) do
    Raven.configuration.breadcrumbs_logger = []
    # revert the injected methods to keep other specs clean
    Raven::Breadcrumbs::SentryLogger.module_eval do
      def add(*args)
        super
      end
    end
  end

  it "captures correct data" do
    get "/exception"

    expect(response.status).to eq(500)
    event = JSON.parse!(Raven.client.transport.events.first[1])
    breadcrumbs = event.dig("breadcrumbs", "values")
    expect(breadcrumbs.count).to eq(1)
    expect(breadcrumbs.first).to match(
      {
        "category" => "Processing by HelloController#exception as HTML",
        "data" => {},
        "level" => "info",
        "message" => "Processing by HelloController#exception as HTML",
        "timestamp" => anything,
        "type" => "info"
      }
    )
  end
end
