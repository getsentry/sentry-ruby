# frozen_string_literal: true

RSpec.describe Sentry::DataCollection do
  subject(:data_collection) { described_class.new }

  describe ".backfill" do
    it "uses the send_default_pii=false defaults" do
      configuration = Sentry::Configuration.new
      data_collection = described_class.backfill(configuration)

      expect(data_collection.user_info).to eq(false)
      expect(data_collection.cookies.mode).to eq(:off)
      expect(data_collection.http_headers.request.mode).to eq(:off)
      expect(data_collection.http_headers.response.mode).to eq(:off)
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

  describe "defaults" do
    it "uses the defaults from the Data Collection specification" do
      expect(data_collection.user_info).to eq(true)
      expect(data_collection.cookies.mode).to eq(:deny_list)
      expect(data_collection.cookies.terms).to be_nil
      expect(data_collection.http_headers.request.mode).to eq(:deny_list)
      expect(data_collection.http_headers.request.terms).to be_nil
      expect(data_collection.http_headers.response.mode).to eq(:deny_list)
      expect(data_collection.http_headers.response.terms).to be_nil
      expect(data_collection.http_bodies).to be_nil
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
