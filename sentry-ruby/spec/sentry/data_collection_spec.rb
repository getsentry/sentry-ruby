# frozen_string_literal: true

RSpec.describe Sentry::DataCollection do
  subject(:data_collection) { described_class.new }

  describe ".filter" do
    it "applies the default sensitive denylist" do
      expect(described_class.filter("token" => "secret", "page" => "2")).to eq(
        "token" => "[Filtered]",
        "page" => "2"
      )
    end
  end

  describe ".backfill" do
    it "uses the send_default_pii=false defaults" do
      configuration = Sentry::Configuration.new
      data_collection = described_class.backfill(configuration)

      expect(data_collection.user_info).to eq(false)
      expect(data_collection.cookies.mode).to eq(:off)
      expect(data_collection.http_headers.request.mode).to eq(:deny_list)
      expect(data_collection.http_headers.request.terms).to eq(described_class::PII_HEADER_SNIPPETS)
      expect(data_collection.http_headers.response.mode).to eq(:deny_list)
      expect(data_collection.http_headers.response.terms).to eq(described_class::PII_HEADER_SNIPPETS)
      expect(data_collection.http_bodies).to eq([])
      expect(data_collection.url_query_params.mode).to eq(:off)
      expect(data_collection.database_query_data).to eq(false)
      expect(data_collection.graphql.document).to eq(false)
      expect(data_collection.graphql.variables).to eq(false)
      expect(data_collection.queues).to eq(false)
      expect(data_collection.stack_frame_variables).to eq(false)
      expect(data_collection.frame_context_lines).to eq(3)
    end

    it "uses the send_default_pii=true defaults when enabled later" do
      configuration = Sentry::Configuration.new
      configuration.send_default_pii = true

      expect(configuration.data_collection.user_info).to eq(true)
      expect(configuration.data_collection.cookies.mode).to eq(:deny_list)
    end
  end

  describe "#collect_incoming_http_body?" do
    it "collects the body when http_bodies is nil" do
      data_collection.http_bodies = nil

      expect(data_collection.collect_incoming_http_body?).to eq(true)
    end

    it "collects the body when incoming requests are configured" do
      data_collection.http_bodies = [:incoming_request]

      expect(data_collection.collect_incoming_http_body?).to eq(true)
    end

    it "does not collect the body when incoming requests are not configured" do
      data_collection.http_bodies = [:outgoing_request]

      expect(data_collection.collect_incoming_http_body?).to eq(false)
    end
  end

  describe "defaults" do
    it "uses a mutable copy of the body type defaults" do
      data_collection.http_bodies.delete(:incoming_request)

      expect(data_collection.http_bodies).not_to include(:incoming_request)
      expect(described_class::BODY_TYPES).to include(:incoming_request)
    end

    it "uses the defaults from the Data Collection specification" do
      expect(data_collection.user_info).to eq(true)
      expect(data_collection.cookies.mode).to eq(:deny_list)
      expect(data_collection.cookies.terms).to be_nil
      expect(data_collection.http_headers.request.mode).to eq(:deny_list)
      expect(data_collection.http_headers.request.terms).to eq(nil)
      expect(data_collection.http_headers.response.mode).to eq(:deny_list)
      expect(data_collection.http_headers.request.terms).to eq(nil)
      expect(data_collection.http_bodies).to eq(described_class::BODY_TYPES)
      expect(data_collection.url_query_params.mode).to eq(:deny_list)
      expect(data_collection.url_query_params.terms).to be_nil
      expect(data_collection.database_query_data).to eq(true)
      expect(data_collection.graphql.document).to eq(true)
      expect(data_collection.graphql.variables).to eq(true)
      expect(data_collection.queues).to eq(true)
      expect(data_collection.stack_frame_variables).to eq(false)
      expect(data_collection.frame_context_lines).to eq(3)
    end
  end

  describe "constants" do
    it "defines the supported modes" do
      expect(described_class::MODES).to eq(%i[off deny_list allow_list])
    end

    it "defines the supported body types" do
      expect(described_class::BODY_TYPES).to eq(
        %i[incoming_request outgoing_request incoming_response outgoing_response]
      )
    end
  end

  describe "nested configuration objects" do
    it "supports configuring key-value collection modes and terms" do
      data_collection.cookies.mode = :allow_list
      data_collection.cookies.terms = ["page"]

      expect(data_collection.cookies.mode).to eq(:allow_list)
      expect(data_collection.cookies.terms).to eq(["page"])
    end

    it "supports configuring request and response headers independently" do
      data_collection.http_headers.request.mode = :off
      data_collection.http_headers.response.terms = ["x-request-id"]

      expect(data_collection.http_headers.request.mode).to eq(:off)
      expect(data_collection.http_headers.response.terms).to eq(["x-request-id"])
    end

    it "supports configuring GraphQL fields independently" do
      data_collection.graphql.document = false
      data_collection.graphql.variables = false

      expect(data_collection.graphql.document).to eq(false)
      expect(data_collection.graphql.variables).to eq(false)
    end
  end
end
