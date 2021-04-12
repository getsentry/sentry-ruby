require "spec_helper"

# we can't stub/mock these requests with tools like webmock
# because they generally stub the request on the same level as the patch works
RSpec.describe Sentry::Net::HTTP do
  let(:string_io) { StringIO.new }
  let(:logger) do
    ::Logger.new(string_io)
  end

  context "with http_logger" do
    before do
      perform_basic_setup do |config|
        config.breadcrumbs_logger = [:http_logger]
        config.transport.transport_class = Sentry::HTTPTransport
        config.logger = logger
        # the dsn needs to have a real host so we can make a real connection before sending a failed request
        config.dsn = 'https://foobarbaz@o447951.ingest.sentry.io/5434472'
      end
    end

    it "adds http breadcrumbs" do
      response = Net::HTTP.get_response(URI("https://github.com/getsentry/sentry-ruby?foo=bar"))

      expect(response.code).to eq("200")
      crumb = Sentry.get_current_scope.breadcrumbs.peek
      expect(crumb.category).to eq("net.http")
      expect(crumb.data).to eq({ status: 200, method: "GET", url: "https://github.com/getsentry/sentry-ruby" })
    end

    it "doesn't record breadcrumb for the SDK's request" do
      Sentry.capture_message("foo")

      # make sure the request was actually made
      expect(string_io.string).to match(/bad sentry DSN public key/)
      expect(Sentry.get_current_scope.breadcrumbs.peek).to be_nil
    end
  end

  context "with tracing enabled" do
    before do
      perform_basic_setup do |config|
        config.traces_sample_rate = 1.0
        config.transport.transport_class = Sentry::HTTPTransport
        config.logger = logger
        # the dsn needs to have a real host so we can make a real connection before sending a failed request
        config.dsn = 'https://foobarbaz@o447951.ingest.sentry.io/5434472'
      end
    end

    it "records the request's span" do
      transaction = Sentry.start_transaction
      Sentry.get_current_scope.set_span(transaction)

      response = Net::HTTP.get_response(URI("https://github.com/getsentry/sentry-ruby"))

      expect(response.code).to eq("200")
      expect(transaction.span_recorder.spans.count).to eq(2)

      request_span = transaction.span_recorder.spans.last
      expect(request_span.op).to eq("net.http")
      expect(request_span.start_timestamp).not_to be_nil
      expect(request_span.timestamp).not_to be_nil
      expect(request_span.start_timestamp).not_to eq(request_span.timestamp)
      expect(request_span.description).to eq("GET https://github.com/getsentry/sentry-ruby")
      expect(request_span.data).to eq({ status: 200 })
    end

    it "doesn't record span for the SDK's request" do
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

      response = Net::HTTP.get_response(URI("https://github.com/getsentry/sentry-ruby"))
      expect(response.code).to eq("200")

      response = Net::HTTP.get_response(URI("https://github.com/getsentry/sentry-foo"))
      expect(response.code).to eq("404")

      expect(transaction.span_recorder.spans.count).to eq(3)

      request_span = transaction.span_recorder.spans[1]
      expect(request_span.op).to eq("net.http")
      expect(request_span.start_timestamp).not_to be_nil
      expect(request_span.timestamp).not_to be_nil
      expect(request_span.start_timestamp).not_to eq(request_span.timestamp)
      expect(request_span.description).to eq("GET https://github.com/getsentry/sentry-ruby")
      expect(request_span.data).to eq({ status: 200 })

      request_span = transaction.span_recorder.spans[2]
      expect(request_span.op).to eq("net.http")
      expect(request_span.start_timestamp).not_to be_nil
      expect(request_span.timestamp).not_to be_nil
      expect(request_span.start_timestamp).not_to eq(request_span.timestamp)
      expect(request_span.description).to eq("GET https://github.com/getsentry/sentry-foo")
      expect(request_span.data).to eq({ status: 404 })
    end

    context "with unsampled transaction" do
      it "doesn't do anything" do
        transaction = Sentry.start_transaction(sampled: false)
        expect(transaction).not_to receive(:start_child)
        Sentry.get_current_scope.set_span(transaction)

        response = Net::HTTP.get_response(URI("https://github.com/getsentry/sentry-ruby"))

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
      response = Net::HTTP.get_response(URI("https://www.google.com"))
      expect(response.code).to eq("200")

      expect(Sentry.get_current_scope.get_transaction).to eq(nil)
      expect(Sentry.get_current_scope.breadcrumbs.peek).to eq(nil)
    end
  end

  context "without SDK" do
    it "doesn't affect the HTTP lib anything" do
      response = Net::HTTP.get_response(URI("https://www.google.com"))
      expect(response.code).to eq("200")
    end
  end
end
