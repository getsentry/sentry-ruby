require "spec_helper"

RSpec.describe "Sentry::Breadcrumbs::ActiveSupportLogger", type: :request do
  before do
    make_basic_app do |sentry_config|
      sentry_config.breadcrumbs_logger = [:active_support_logger]
      sentry_config.traces_sample_rate = 1.0
    end
  end

  after do
    require 'sentry/rails/breadcrumb/active_support_logger'
    Sentry::Rails::Breadcrumb::ActiveSupportLogger.detach
    # even though we cleanup breadcrumbs in the rack middleware
    # Breadcrumbs::ActiveSupportLogger subscribes to "every" instrumentation
    # so it'll create other instrumentations "after" the request is finished
    # and we should clear those as well
    Sentry.get_current_scope.clear_breadcrumbs
  end

  let(:transport) do
    Sentry.get_current_client.transport
  end

  let(:event) do
    transport.events.first.to_json_compatible
  end

  after do
    transport.events = []
  end

  it "captures correct data of exception requests" do
    get "/exception"

    expect(response.status).to eq(500)
    breadcrumbs = event.dig("breadcrumbs", "values")
    expect(breadcrumbs.count).to eq(2)

    breadcrumb = breadcrumbs.detect { |b| b["category"] == "process_action.action_controller" }
    expect(breadcrumb["data"]).to include(
      {
        "controller" => "HelloController",
        "action" => "exception",
        "params" => { "controller" => "hello", "action" => "exception" },
        "format" => "html",
        "method" => "GET", "path" => "/exception",
      }
    )
    expect(breadcrumb["data"].keys).not_to include("headers")
    expect(breadcrumb["data"].keys).not_to include("request")
    expect(breadcrumb["data"].keys).not_to include("response")
  end

  it "captures correct request data of normal requests" do
    p = Post.create!

    get "/posts/#{p.id}"

    breadcrumbs = event.dig("breadcrumbs", "values")

    breadcrumb = breadcrumbs.detect { |b| b["category"] == "process_action.action_controller" }
    expect(breadcrumb["data"]).to include(
      {
        "controller" => "PostsController",
        "action" => "show",
        "params" => { "controller" => "posts", "action" => "show", "id" => p.id.to_s },
        "format" => "html",
        "method" => "GET", "path" => "/posts/#{p.id}",
      }
    )
    expect(breadcrumb["data"].keys).not_to include("headers")
    expect(breadcrumb["data"].keys).not_to include("request")
    expect(breadcrumb["data"].keys).not_to include("response")
  end

  it "ignores exception data" do
    get "/view_exception"

    expect(event.dig("breadcrumbs", "values", -1, "data").keys).not_to include("exception")
    expect(event.dig("breadcrumbs", "values", -1, "data").keys).not_to include("exception_object")
  end

  it "ignores events that doesn't have a started timestamp" do
    expect do
      ActiveSupport::Notifications.publish "foo", Object.new
    end.not_to raise_error

    expect(transport.events).to be_empty
  end
end
