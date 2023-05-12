require "spec_helper"
require 'contexts/with_request_mock'

RSpec.describe :http_logger do
  include_context "with request mock"

  let(:string_io) { StringIO.new }
  let(:logger) do
    ::Logger.new(string_io)
  end

  before do
    perform_basic_setup do |config|
      config.breadcrumbs_logger = [:http_logger]
      config.transport.transport_class = Sentry::HTTPTransport
      config.logger = logger
      # the dsn needs to have a real host so we can make a real connection before sending a failed request
      config.dsn = 'http://foobarbaz@o447951.ingest.sentry.io/5434472'
    end
  end

  context "with config.send_default_pii = true" do
    before do
      Sentry.configuration.send_default_pii = true
    end

    it "adds http breadcrumbs with query string & request body" do
      stub_normal_response

      response = Net::HTTP.get_response(URI("http://example.com/path?foo=bar"))

      expect(response.code).to eq("200")
      crumb = Sentry.get_current_scope.breadcrumbs.peek
      expect(crumb.category).to eq("net.http")
      expect(crumb.data).to eq({ status: 200, method: "GET", url: "http://example.com/path", query: "foo=bar", body: nil })

      http = Net::HTTP.new("example.com")
      request = Net::HTTP::Get.new("/path?foo=bar")
      response = http.request(request)

      expect(response.code).to eq("200")
      crumb = Sentry.get_current_scope.breadcrumbs.peek
      expect(crumb.category).to eq("net.http")
      expect(crumb.data).to eq({ status: 200, method: "GET", url: "http://example.com/path", query: "foo=bar", body: nil })

      request = Net::HTTP::Post.new("/path?foo=bar")
      request.body = 'quz=qux'
      response = http.request(request)

      expect(response.code).to eq("200")
      crumb = Sentry.get_current_scope.breadcrumbs.peek
      expect(crumb.category).to eq("net.http")
      expect(crumb.data).to eq(
        { status: 200, method: "POST", url: "http://example.com/path", query: "foo=bar", body: 'quz=qux' }
      )
    end
  end

  context "with config.send_default_pii = false" do
    before do
      Sentry.configuration.send_default_pii = false
    end

    it "adds http breadcrumbs without query string & request body" do
      stub_normal_response

      response = Net::HTTP.get_response(URI("http://example.com/path?foo=bar"))

      expect(response.code).to eq("200")
      crumb = Sentry.get_current_scope.breadcrumbs.peek
      expect(crumb.category).to eq("net.http")
      expect(crumb.data).to eq({ status: 200, method: "GET", url: "http://example.com/path" })

      http = Net::HTTP.new("example.com")
      request = Net::HTTP::Get.new("/path?foo=bar")
      response = http.request(request)

      expect(response.code).to eq("200")
      crumb = Sentry.get_current_scope.breadcrumbs.peek
      expect(crumb.category).to eq("net.http")
      expect(crumb.data).to eq({ status: 200, method: "GET", url: "http://example.com/path" })

      request = Net::HTTP::Post.new("/path?foo=bar")
      request.body = 'quz=qux'
      response = http.request(request)

      expect(response.code).to eq("200")
      crumb = Sentry.get_current_scope.breadcrumbs.peek
      expect(crumb.category).to eq("net.http")
      expect(crumb.data).to eq({ status: 200, method: "POST", url: "http://example.com/path" })
    end
  end

  it "doesn't record breadcrumb for the SDK's request" do
    stub_sentry_response

    Sentry.capture_message("foo")

    # make sure the request was actually made
    expect(string_io.string).to match(/bad sentry DSN public key/)
    expect(Sentry.get_current_scope.breadcrumbs.peek).to be_nil
  end

  context "when dsn is nil" do
    before do
      Sentry.configuration.instance_variable_set(:@dsn, nil)
    end
    it "doesn't cause error" do
      stub_normal_response

      response = Net::HTTP.get_response(URI("http://example.com/path?foo=bar"))

      expect(response.code).to eq("200")
      crumb = Sentry.get_current_scope.breadcrumbs.peek
      expect(crumb.category).to eq("net.http")
      expect(crumb.data).to eq({ status: 200, method: "GET", url: "http://example.com/path" })
    end
  end
end
