# frozen_string_literal: true

require "contexts/with_request_mock"
require "excon"

RSpec.describe "Sentry::Excon" do
  include Sentry::Utils::HttpTracing
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
      Excon.stub({}, { body: "", status: 200 })

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
        config.sdk_logger = logger
        # the dsn needs to have a real host so we can make a real connection before sending a failed request
        config.dsn = "http://foobarbaz@o447951.ingest.sentry.io/5434472"
        config.enabled_patches += [:excon] unless config.enabled_patches.include?(:excon)
      end
    end

    describe "data collection" do
      describe "query parameters" do
        def perform_get_request(query: "token=secret&page=5")
          transaction = Sentry.start_transaction
          Sentry.get_current_scope.set_span(transaction)
          Excon.stub({}, { body: "", status: 200 })
          Excon.get("http://example.com/path?#{query}", mock: true)
          transaction
        end

        it "does not collect them when the mode is off" do
          Sentry.configuration.data_collection.url_query_params.mode = :off
          transaction = perform_get_request

          expect(transaction.span_recorder.spans.last.data).not_to have_key("http.query")
          expect(transaction.span_recorder.spans.last.data["url"]).to eq("http://example.com/path")
        end

        it "filters sensitive values in deny-list mode" do
          Sentry.configuration.data_collection.url_query_params.mode = :deny_list
          transaction = perform_get_request

          expect(transaction.span_recorder.spans.last.data["http.query"]).to eq(
            "token=[Filtered]&page=5"
          )
          expect(transaction.span_recorder.spans.last.data["url"]).to eq(
            "http://example.com/path?token=[Filtered]&page=5"
          )
        end

        it "collects only allowed values in allow-list mode" do
          Sentry.configuration.data_collection.url_query_params.mode = :allow_list
          Sentry.configuration.data_collection.url_query_params.terms = ["page"]
          transaction = perform_get_request(query: "another=value&page=5")

          expect(transaction.span_recorder.spans.last.data["http.query"]).to eq(
            "another=[Filtered]&page=5"
          )
          expect(transaction.span_recorder.spans.last.data["url"]).to eq(
            "http://example.com/path?another=[Filtered]&page=5"
          )
        end
      end

      describe "request bodies" do
        before do
          Sentry.configuration.breadcrumbs_logger = [:http_logger]
        end

        def perform_post_request
          transaction = Sentry.start_transaction
          Sentry.get_current_scope.set_span(transaction)
          Excon.stub({}, { body: "", status: 200 })
          Excon.post("http://example.com/path", body: "secret body", mock: true)
        end

        it "collects them when all body types are enabled" do
          Sentry.configuration.data_collection.http_bodies = nil
          perform_post_request

          expect(Sentry.get_current_scope.breadcrumbs.peek.data[:body]).to eq("secret body")
        end

        it "collects them when outgoing requests are enabled" do
          Sentry.configuration.data_collection.http_bodies = [:outgoing_request]
          perform_post_request

          expect(Sentry.get_current_scope.breadcrumbs.peek.data[:body]).to eq("secret body")
        end

        it "does not collect them when body types are disabled" do
          Sentry.configuration.data_collection.http_bodies = []
          perform_post_request

          expect(Sentry.get_current_scope.breadcrumbs.peek.data).not_to have_key(:body)
        end
      end
    end

    context "with config.send_default_pii = true" do
      before do
        Sentry.configuration.send_default_pii = true
        Sentry.configuration.breadcrumbs_logger = [:http_logger]
      end

      it "records the request's span with query string in data" do
        Excon.stub({}, { body: "", status: 200 })

        transaction = Sentry.start_transaction
        Sentry.get_current_scope.set_span(transaction)

        response = Excon.get("http://example.com/path?foo=bar", mock: true)

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
          "url" => "http://example.com/path?foo=bar",
          "http.request.method" => "GET",
          "http.query" => "foo=bar"
        })
      end

      it "records the request's span with advanced query string in data" do
        Excon.stub({}, { body: "", status: 200 })

        transaction = Sentry.start_transaction
        Sentry.get_current_scope.set_span(transaction)

        connection = Excon.new("http://example.com/path")
        response = connection.get(mock: true, query: "foo=bar&baz[]=1&baz[]=2&qux[a]=1&qux[b]=2")

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
          "url" => "http://example.com/path?foo=bar&baz[]=1&baz[]=2&qux[a]=1&qux[b]=2",
          "http.request.method" => "GET",
          "http.query" => "foo=bar&baz[]=1&baz[]=2&qux[a]=1&qux[b]=2"
        })
      end

      context "breadcrumbs" do
        it "records correct data in breadcrumbs" do
          Excon.stub({}, { body: "", status: 200 })

          transaction = Sentry.start_transaction
          Sentry.get_current_scope.set_span(transaction)

          _response = Excon.get("http://example.com/path?foo=bar", mock: true)

          transaction.span_recorder.spans.last

          crumb = Sentry.get_current_scope.breadcrumbs.peek
          expect(crumb.category).to eq("http")
          expect(crumb.level).to eq(:info)
          expect(crumb.data[:status]).to eq(200)
          expect(crumb.data[:method]).to eq("GET")
          expect(crumb.data[:url]).to eq("http://example.com/path")
          expect(crumb.data[:query]).to eq("foo=bar")
          expect(crumb.data[:body]).to be(nil)
        end

        { 200 => :info, 400 => :warning, 500 => :error }.each do |status, level|
          it "has correct level #{level} for #{status}" do
            Excon.stub({}, { body: "", status: status })

            transaction = Sentry.start_transaction
            Sentry.get_current_scope.set_span(transaction)

            _response = Excon.get("http://example.com/path?foo=bar", mock: true)

            transaction.span_recorder.spans.last

            crumb = Sentry.get_current_scope.breadcrumbs.peek
            expect(crumb.level).to eq(level)
            expect(crumb.data[:status]).to eq(status)
          end
        end
      end
    end

    context "with config.send_default_pii = false" do
      before do
        Sentry.configuration.send_default_pii = false
      end

      it "records the request's span without query string" do
        Excon.stub({}, { body: "", status: 200 })

        transaction = Sentry.start_transaction
        Sentry.get_current_scope.set_span(transaction)

        response = Excon.get("http://example.com/path?foo=bar", mock: true)

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
        Excon.stub({}, { body: "", status: 200 })
        response = Excon.get("http://example.com/path?foo=bar", mock: true)
        expect(response.status).to eq(200)

        Excon.stub({}, { body: "", status: 404 })
        response = Excon.get("http://example.com/path?foo=bar", mock: true)
        expect(response.status).to eq(404)

        verify_spans(transaction)
      end

      context "with nested span" do
        let(:span) { transaction.start_child(op: "child span") }

        before do
          Sentry.get_current_scope.set_span(span)
        end

        it "attaches http spans to the span instead of top-level transaction" do
          Excon.stub({}, { body: "", status: 200 })
          response = Excon.get("http://example.com/path?foo=bar", mock: true)
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
      Excon.stub({}, { body: "", status: 200 })

      response = Excon.get("http://example.com/path")
      expect(response.status).to eq(200)
    end
  end
end
