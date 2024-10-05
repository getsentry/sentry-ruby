# frozen_string_literal: true

require "faraday"
require_relative "../spec_helper"

RSpec.describe Sentry::Faraday do
  before(:all) do
    perform_basic_setup do |config|
      config.enabled_patches << :faraday
      config.traces_sample_rate = 1.0
      config.logger = ::Logger.new(StringIO.new)
    end
  end

  after(:all) do
    Sentry.configuration.enabled_patches = Sentry::Configuration::DEFAULT_PATCHES
  end

  context "with tracing enabled" do
    let(:http) do
      Faraday.new(url) do |f|
        f.request :json

        f.adapter Faraday::Adapter::Test do |stub|
          stub.get("/test") do
            [200, { "Content-Type" => "text/html" }, "<h1>hello world</h1>"]
          end
        end
      end
    end

    let(:url) { "http://example.com" }

    it "records the request's span" do
      transaction = Sentry.start_transaction
      Sentry.get_current_scope.set_span(transaction)

      _response = http.get("/test")

      request_span = transaction.span_recorder.spans.last

      expect(request_span.op).to eq("http.client")
      expect(request_span.origin).to eq("auto.http.faraday")
      expect(request_span.start_timestamp).not_to be_nil
      expect(request_span.timestamp).not_to be_nil
      expect(request_span.start_timestamp).not_to eq(request_span.timestamp)
      expect(request_span.description).to eq("GET http://example.com/test")

      expect(request_span.data).to eq({
        "http.response.status_code" => 200,
        "url" => "http://example.com/test",
        "http.request.method" => "GET"
      })
    end
  end

  context "with config.send_default_pii = true" do
    let(:http) do
      Faraday.new(url) do |f|
        f.adapter Faraday::Adapter::Test do |stub|
          stub.get("/test") do
            [200, { "Content-Type" => "text/html" }, "<h1>hello world</h1>"]
          end

          stub.post("/test") do
            [200, { "Content-Type" => "application/json" }, { hello: "world" }.to_json]
          end
        end
      end
    end

    let(:url) { "http://example.com" }

    before do
      Sentry.configuration.send_default_pii = true
      Sentry.configuration.breadcrumbs_logger = [:http_logger]
    end

    it "records the request's span with query string in data" do
      transaction = Sentry.start_transaction
      Sentry.get_current_scope.set_span(transaction)

      _response = http.get("/test?foo=bar")

      request_span = transaction.span_recorder.spans.last

      expect(request_span.description).to eq("GET http://example.com/test")

      expect(request_span.data).to eq({
        "http.response.status_code" => 200,
        "url" => "http://example.com/test",
        "http.request.method" => "GET",
        "http.query" => "foo=bar"
      })
    end

    it "records breadcrumbs" do
      transaction = Sentry.start_transaction
      Sentry.get_current_scope.set_span(transaction)

      _response = http.get("/test?foo=bar")

      transaction.span_recorder.spans.last

      crumb = Sentry.get_current_scope.breadcrumbs.peek

      expect(crumb.category).to eq("http")
      expect(crumb.data[:status]).to eq(200)
      expect(crumb.data[:method]).to eq("GET")
      expect(crumb.data[:url]).to eq("http://example.com/test")
      expect(crumb.data[:query]).to eq("foo=bar")
      expect(crumb.data[:body]).to be(nil)
    end

    it "records POST request body" do
      transaction = Sentry.start_transaction
      Sentry.get_current_scope.set_span(transaction)

      body = { foo: "bar" }.to_json
      _response = http.post("/test?foo=bar", body, "Content-Type" => "application/json")

      request_span = transaction.span_recorder.spans.last

      expect(request_span.description).to eq("POST http://example.com/test")

      expect(request_span.data).to eq({
        "http.response.status_code" => 200,
        "url" => "http://example.com/test",
        "http.request.method" => "POST",
        "http.query" => "foo=bar"
      })

      crumb = Sentry.get_current_scope.breadcrumbs.peek

      expect(crumb.data[:body]).to eq(body)
    end

    context "with custom trace_propagation_targets" do
      let(:http) do
        Faraday.new(url) do |f|
          f.adapter Faraday::Adapter::Test do |stub|
            stub.get("/test") do
              [200, { "Content-Type" => "text/html" }, "<h1>hello world</h1>"]
            end
          end
        end
      end

      before do
        Sentry.configuration.trace_propagation_targets = ["example.com", /foobar.org\/api\/v2/]
      end

      context "when the request is not to the same target" do
        let(:url) { "http://another.site" }

        it "doesn't add sentry headers to outgoing requests to different target" do
          transaction = Sentry.start_transaction
          Sentry.get_current_scope.set_span(transaction)

          response = http.get("/test")

          request_span = transaction.span_recorder.spans.last

          expect(request_span.description).to eq("GET #{url}/test")

          expect(request_span.data).to eq({
            "http.response.status_code" => 200,
            "url" => "#{url}/test",
            "http.request.method" => "GET"
          })

          expect(response.headers.key?("sentry-trace")).to eq(false)
          expect(response.headers.key?("baggage")).to eq(false)
        end
      end

      context "when the request is to the same target" do
        let(:url) { "http://example.com" }

        before do
          Sentry.configuration.trace_propagation_targets = ["example.com"]
        end

        it "adds sentry headers to outgoing requests" do
          transaction = Sentry.start_transaction
          Sentry.get_current_scope.set_span(transaction)

          response = http.get("/test")

          request_span = transaction.span_recorder.spans.last

          expect(request_span.description).to eq("GET #{url}/test")

          expect(request_span.data).to eq({
            "http.response.status_code" => 200,
            "url" => "#{url}/test",
            "http.request.method" => "GET"
          })

          expect(response.env.request_headers.key?("sentry-trace")).to eq(true)
          expect(response.env.request_headers.key?("baggage")).to eq(true)
        end
      end

      context "when the request's url configured target regexp" do
        let(:url) { "http://example.com" }

        before do
          Sentry.configuration.trace_propagation_targets = [/example/]
        end

        it "adds sentry headers to outgoing requests" do
          transaction = Sentry.start_transaction
          Sentry.get_current_scope.set_span(transaction)

          response = http.get("/test")

          request_span = transaction.span_recorder.spans.last

          expect(request_span.description).to eq("GET #{url}/test")

          expect(request_span.data).to eq({
            "http.response.status_code" => 200,
            "url" => "#{url}/test",
            "http.request.method" => "GET"
          })

          expect(response.env.request_headers.key?("sentry-trace")).to eq(true)
          expect(response.env.request_headers.key?("baggage")).to eq(true)
        end
      end
    end
  end

  context "when adapter is net/http" do
    let(:http) do
      Faraday.new(url) do |f|
        f.request :json
        f.adapter :net_http
      end
    end

    let(:url) { "http://example.com" }

    it "skips instrumentation" do
      transaction = Sentry.start_transaction
      Sentry.get_current_scope.set_span(transaction)

      _response = http.get("/test")

      request_span = transaction.span_recorder.spans.last

      expect(request_span.op).to eq("http.client")
      expect(request_span.origin).to eq("auto.http.net_http")

      expect(transaction.span_recorder.spans.map(&:origin)).not_to include("auto.http.faraday")
    end
  end

  context "when Sentry is not initialized" do
    let(:http) do
      Faraday.new(url) do |f|
        f.adapter Faraday::Adapter::Test do |stub|
          stub.get("/test") do
            [200, { "Content-Type" => "text/html" }, "<h1>hello world</h1>"]
          end
        end
      end
    end

    let(:url) { "http://example.com" }

    it "skips instrumentation" do
      allow(Sentry).to receive(:initialized?).and_return(false)

      response = http.get("/test")

      expect(response.status).to eq(200)
    end
  end
end
