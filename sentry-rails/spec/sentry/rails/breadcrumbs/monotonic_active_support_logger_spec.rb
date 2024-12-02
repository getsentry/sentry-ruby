# frozen_string_literal: true

require "spec_helper"


RSpec.describe "Sentry::Breadcrumbs::MonotonicActiveSupportLogger", type: :request do
  after do
    # even though we cleanup breadcrumbs in the rack middleware
    # Breadcrumbs::MonotonicActiveSupportLogger subscribes to "every" instrumentation
    # so it'll create other instrumentations "after" the request is finished
    # and we should clear those as well
    Sentry.get_current_scope.clear_breadcrumbs
  end

  let(:transport) do
    Sentry.get_current_client.transport
  end

  let(:breadcrumb_buffer) do
    Sentry.get_current_scope.breadcrumbs
  end

  let(:event) do
    transport.events.first.to_json_compatible
  end
  context "without tracing" do
    before do
      make_basic_app do |sentry_config|
        sentry_config.breadcrumbs_logger = [:monotonic_active_support_logger]
      end
    end

    context "given a Rails version < 6.1", skip: Rails.version.to_f >= 6.1 do
      it "does not run instrumentation" do
        get "/exception"

        breadcrumbs = event.dig("breadcrumbs", "values")
        expect(breadcrumbs.count).to be_zero
      end
    end

    context "given a Rails version >= 6.1", skip: Rails.version.to_f < 6.1 do
      after do
        Sentry::Rails::Breadcrumb::MonotonicActiveSupportLogger.detach
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
            "method" => "GET", "path" => "/exception"
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

      it "ignores events that doesn't have a float as started attributes" do
        expect do
          ActiveSupport::Notifications.publish "foo", Time.now
        end.not_to raise_error

        expect(breadcrumb_buffer.count).to be_zero
      end
    end
  end

  context "with tracing" do
    before do
      make_basic_app do |sentry_config|
        sentry_config.breadcrumbs_logger = [:monotonic_active_support_logger]
        sentry_config.traces_sample_rate = 1.0
      end
    end

    context "given a Rails version < 6.1", skip: Rails.version.to_f >= 6.1 do
      it "does not run instrumentation" do
        get "/exception"

        breadcrumbs = event.dig("breadcrumbs", "values")
        expect(breadcrumbs.count).to be_zero
      end
    end

    context "given a Rails version >= 6.1", skip: Rails.version.to_f < 6.1 do
      after do
        Sentry::Rails::Breadcrumb::MonotonicActiveSupportLogger.detach
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
            "method" => "GET", "path" => "/posts/#{p.id}"
          }
        )
        expect(breadcrumb["data"].keys).not_to include("headers")
        expect(breadcrumb["data"].keys).not_to include("request")
        expect(breadcrumb["data"].keys).not_to include("response")
      end

      it "doesn't add internal start timestamp payload to breadcrumbs data" do
        p = Post.create!

        get "/posts/#{p.id}"

        expect(transport.events.count).to eq(1)

        transaction = transport.events.last.to_hash
        breadcrumbs = transaction[:breadcrumbs][:values]
        process_action_crumb = breadcrumbs.last
        expect(process_action_crumb[:category]).to eq("process_action.action_controller")
        expect(process_action_crumb[:data].has_key?(Sentry::Rails::Tracing::START_TIMESTAMP_NAME)).to eq(false)
      end
    end
  end
end
