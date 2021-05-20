require "spec_helper"
require "webmock"

# because our patch on Net::HTTP is relatively low-level, we need to stub methods on socket level
# which is not supported by most of the http mocking library
# so we need to put something together ourselves
RSpec.describe Sentry::Net::HTTP do
  let(:string_io) { StringIO.new }
  let(:logger) do
    ::Logger.new(string_io)
  end

  original_buffered_io = Net::BufferedIO

  before(:all) do
    Net.send(:const_set, :BufferedIO, Net::WebMockNetBufferedIO)
  end

  after(:all) do
    Net.send(:const_set, :BufferedIO, original_buffered_io)
  end

  class FakeSocket < StringIO
    def setsockopt(*args); end
  end

  before do
    allow(TCPSocket).to receive(:open).and_return(FakeSocket.new)
  end

  def stub_sentry_response
    # use bad request as an example is easier for verifying with error messages
    fake_response = Net::HTTPResponse.new("1.0", "400", "")
    allow(fake_response).to receive(:body).and_return(JSON.generate({ data: "bad sentry DSN public key" }))
    allow_any_instance_of(Net::HTTP).to receive(:transport_request).and_return(fake_response)
  end

  def stub_normal_response(code: "200")
    fake_response = Net::HTTPResponse.new("1.0", code, "")
    allow(fake_response).to receive(:body).and_return("")
    allow_any_instance_of(Net::HTTP).to receive(:transport_request).and_return(fake_response)
  end

  context "with http_logger" do
    before do
      perform_basic_setup do |config|
        config.breadcrumbs_logger = [:http_logger]
        config.transport.transport_class = Sentry::HTTPTransport
        config.logger = logger
        # the dsn needs to have a real host so we can make a real connection before sending a failed request
        config.dsn = 'http://foobarbaz@o447951.ingest.sentry.io/5434472'
      end
    end

    it "adds http breadcrumbs" do
      stub_normal_response

      response = Net::HTTP.get_response(URI("http://example.com/path?foo=bar"))

      expect(response.code).to eq("200")
      crumb = Sentry.get_current_scope.breadcrumbs.peek
      expect(crumb.category).to eq("net.http")
      expect(crumb.data).to eq({ status: 200, method: "GET", url: "http://example.com/path" })
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

  context "with tracing enabled" do
    before do
      perform_basic_setup do |config|
        config.traces_sample_rate = 1.0
        config.transport.transport_class = Sentry::HTTPTransport
        config.logger = logger
        # the dsn needs to have a real host so we can make a real connection before sending a failed request
        config.dsn = 'http://foobarbaz@o447951.ingest.sentry.io/5434472'
      end
    end

    it "records the request's span" do
      stub_normal_response

      transaction = Sentry.start_transaction
      Sentry.get_current_scope.set_span(transaction)

      response = Net::HTTP.get_response(URI("http://example.com/path"))

      expect(response.code).to eq("200")
      expect(transaction.span_recorder.spans.count).to eq(2)

      request_span = transaction.span_recorder.spans.last
      expect(request_span.op).to eq("net.http")
      expect(request_span.start_timestamp).not_to be_nil
      expect(request_span.timestamp).not_to be_nil
      expect(request_span.start_timestamp).not_to eq(request_span.timestamp)
      expect(request_span.description).to eq("GET http://example.com/path")
      expect(request_span.data).to eq({ status: 200 })
    end

    it "adds sentry-trace header to the request header" do
      stub_normal_response

      uri = URI("http://example.com/path")
      http = Net::HTTP.new(uri.host, uri.port)
      request = Net::HTTP::Get.new(uri.request_uri)

      transaction = Sentry.start_transaction
      Sentry.get_current_scope.set_span(transaction)

      response = http.request(request)

      expect(response.code).to eq("200")
      expect(string_io.string).to match(
        /\[Tracing\] Adding sentry-trace header to outgoing request:/
      )
      request_span = transaction.span_recorder.spans.last
      expect(request["sentry-trace"]).to eq(request_span.to_sentry_trace)
    end

    it "doesn't record span for the SDK's request" do
      stub_sentry_response

      transaction = Sentry.start_transaction
      Sentry.get_current_scope.set_span(transaction)

      Sentry.capture_message("foo")

      # make sure the request was actually made
      expect(string_io.string).to match(/bad sentry DSN public key/)
      expect(transaction.span_recorder.spans.count).to eq(1)
    end

    it "doesn't mess different requests' data together" do

      transaction = Sentry.start_transaction
      Sentry.get_current_scope.set_span(transaction)

      stub_normal_response(code: "200")
      response = Net::HTTP.get_response(URI("http://example.com/path"))
      expect(response.code).to eq("200")

      stub_normal_response(code: "404")
      response = Net::HTTP.get_response(URI("http://example.com/path"))
      expect(response.code).to eq("404")

      expect(transaction.span_recorder.spans.count).to eq(3)

      request_span = transaction.span_recorder.spans[1]
      expect(request_span.op).to eq("net.http")
      expect(request_span.start_timestamp).not_to be_nil
      expect(request_span.timestamp).not_to be_nil
      expect(request_span.start_timestamp).not_to eq(request_span.timestamp)
      expect(request_span.description).to eq("GET http://example.com/path")
      expect(request_span.data).to eq({ status: 200 })

      request_span = transaction.span_recorder.spans[2]
      expect(request_span.op).to eq("net.http")
      expect(request_span.start_timestamp).not_to be_nil
      expect(request_span.timestamp).not_to be_nil
      expect(request_span.start_timestamp).not_to eq(request_span.timestamp)
      expect(request_span.description).to eq("GET http://example.com/path")
      expect(request_span.data).to eq({ status: 404 })
    end

    context "with unsampled transaction" do
      it "doesn't do anything" do
        stub_normal_response

        transaction = Sentry.start_transaction(sampled: false)
        expect(transaction).not_to receive(:start_child)
        Sentry.get_current_scope.set_span(transaction)

        response = Net::HTTP.get_response(URI("http://example.com/path"))

        expect(response.code).to eq("200")
        expect(transaction.span_recorder.spans.count).to eq(1)
      end
    end
  end

  context "without tracing enabled nor http_logger" do
    before do
      perform_basic_setup
    end

    it "doesn't affect the HTTP lib anything" do
      stub_normal_response

      response = Net::HTTP.get_response(URI("http://example.com/path"))
      expect(response.code).to eq("200")

      expect(Sentry.get_current_scope.get_transaction).to eq(nil)
      expect(Sentry.get_current_scope.breadcrumbs.peek).to eq(nil)
    end
  end

  context "without SDK" do
    it "doesn't affect the HTTP lib anything" do
      stub_normal_response

      response = Net::HTTP.get_response(URI("http://example.com/path"))
      expect(response.code).to eq("200")
    end
  end
end
