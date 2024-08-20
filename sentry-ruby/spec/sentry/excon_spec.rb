require "spec_helper"
require 'contexts/with_request_mock'
require 'excon'

RSpec.describe "Sentry::Excon" do
  include_context "with request mock"

  before do
    Excon.defaults[:mock] = true
  end

  after(:each) do
    Excon.stubs.clear
  end

  let(:string_io) { StringIO.new }
  let(:logger) do
    ::Logger.new(string_io)
  end

  context "with IPv6 addresses" do
    before do
      perform_basic_setup do |config|
        config.traces_sample_rate = 1.0
        config.enabled_patches += [:excon] unless config.enabled_patches.include?(:excon)
      end
    end

    it "correctly parses the short-hand IPv6 addresses" do
      Excon.stub({}, { body: '', status: 200 })

      transaction = Sentry.start_transaction
      Sentry.get_current_scope.set_span(transaction)

      _ = Excon.get("http://[::1]:8080/path", mock: true)

      expect(transaction.span_recorder.spans.count).to eq(2)

      request_span = transaction.span_recorder.spans.last
      expect(request_span.data).to eq(
        { "url" => "http://::1/path", "http.request.method" => "GET", "http.response.status_code" => 200 }
      )
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
        config.enabled_patches += [:excon] unless config.enabled_patches.include?(:excon)
      end
    end

    context "with config.send_default_pii = true" do
      before do
        Sentry.configuration.send_default_pii = true
      end

      it "records the request's span with query string in data" do
        Excon.stub({}, { body: '', status: 200 })

        transaction = Sentry.start_transaction
        Sentry.get_current_scope.set_span(transaction)

        response = Excon.get(URI("http://example.com/path?foo=bar"), mock: true)

        expect(response.status).to eq(200)
        expect(transaction.span_recorder.spans.count).to eq(2)

        request_span = transaction.span_recorder.spans.last
        expect(request_span.op).to eq("http.client")
        expect(request_span.origin).to eq("auto.http.excon")
        expect(request_span.start_timestamp).not_to be_nil
        expect(request_span.timestamp).not_to be_nil
        expect(request_span.start_timestamp).not_to eq(request_span.timestamp)
        expect(request_span.description).to eq("GET http://example.com/path")
        expect(request_span.data).to eq({
          "http.response.status_code" => 200,
          "url" => "http://example.com/path",
          "http.request.method" => "GET",
          "http.query" => "foo=bar"
        })
      end
    end

    context "with config.send_default_pii = false" do
      before do
        Sentry.configuration.send_default_pii = false
      end

      it "records the request's span without query string" do
        Excon.stub({}, { body: '', status: 200 })

        transaction = Sentry.start_transaction
        Sentry.get_current_scope.set_span(transaction)

        response = Excon.get(URI("http://example.com/path?foo=bar"), mock: true)

        expect(response.status).to eq(200)
        expect(transaction.span_recorder.spans.count).to eq(2)

        request_span = transaction.span_recorder.spans.last
        expect(request_span.op).to eq("http.client")
        expect(request_span.origin).to eq("auto.http.excon")
        expect(request_span.start_timestamp).not_to be_nil
        expect(request_span.timestamp).not_to be_nil
        expect(request_span.start_timestamp).not_to eq(request_span.timestamp)
        expect(request_span.description).to eq("GET http://example.com/path")
        expect(request_span.data).to eq({
          "http.response.status_code" => 200,
          "url" => "http://example.com/path",
          "http.request.method" => "GET"
        })
      end
    end

    context "when there're multiple requests" do
      let(:transaction) { Sentry.start_transaction }

      before do
        Sentry.get_current_scope.set_span(transaction)
      end

      def verify_spans(transaction)
        expect(transaction.span_recorder.spans.count).to eq(3)
        expect(transaction.span_recorder.spans[0]).to eq(transaction)

        request_span = transaction.span_recorder.spans[1]
        expect(request_span.op).to eq("http.client")
        expect(request_span.origin).to eq("auto.http.excon")
        expect(request_span.start_timestamp).not_to be_nil
        expect(request_span.timestamp).not_to be_nil
        expect(request_span.start_timestamp).not_to eq(request_span.timestamp)
        expect(request_span.description).to eq("GET http://example.com/path")
        expect(request_span.data).to eq({
          "http.response.status_code" => 200,
          "url" => "http://example.com/path",
          "http.request.method" => "GET"
        })

        request_span = transaction.span_recorder.spans[2]
        expect(request_span.op).to eq("http.client")
        expect(request_span.origin).to eq("auto.http.excon")
        expect(request_span.start_timestamp).not_to be_nil
        expect(request_span.timestamp).not_to be_nil
        expect(request_span.start_timestamp).not_to eq(request_span.timestamp)
        expect(request_span.description).to eq("GET http://example.com/path")
        expect(request_span.data).to eq({
          "http.response.status_code" => 404,
          "url" => "http://example.com/path",
          "http.request.method" => "GET"
        })
      end

      it "doesn't mess different requests' data together" do
        Excon.stub({}, { body: '', status: 200 })
        response = Excon.get(URI("http://example.com/path?foo=bar"), mock: true)
        expect(response.status).to eq(200)

        Excon.stub({}, { body: '', status: 404 })
        response = Excon.get(URI("http://example.com/path?foo=bar"), mock: true)
        expect(response.status).to eq(404)

        verify_spans(transaction)
      end

      context "with nested span" do
        let(:span) { transaction.start_child(op: "child span") }

        before do
          Sentry.get_current_scope.set_span(span)
        end

        it "attaches http spans to the span instead of top-level transaction" do
          Excon.stub({}, { body: '', status: 200 })
          response = Excon.get(URI("http://example.com/path?foo=bar"), mock: true)
          expect(response.status).to eq(200)

          expect(transaction.span_recorder.spans.count).to eq(3)
          expect(span.parent_span_id).to eq(transaction.span_id)
          http_span = transaction.span_recorder.spans.last
          expect(http_span.parent_span_id).to eq(span.span_id)
        end
      end
    end
  end

  context "without SDK" do
    it "doesn't affect the HTTP lib anything" do
      Excon.stub({}, { body: '', status: 200 })

      response = Excon.get(URI("http://example.com/path"))
      expect(response.status).to eq(200)
    end
  end
end
