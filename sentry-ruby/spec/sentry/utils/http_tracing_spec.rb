# frozen_string_literal: true

RSpec.describe Sentry::Utils::HttpTracing do
  subject(:http_tracing) do
    tracing_class = Class.new
    tracing_class.include(Sentry::Utils::HttpTracing)
    tracing_class.new
  end

  before do
    perform_basic_setup do |config|
      config.data_collection.url_query_params.mode = :deny_list
    end
  end

  describe "#format_query" do
    it "formats scalar and array values without encoding them" do
      query = {
        "token" => "[Filtered]",
        "page" => "5",
        "tags[]" => ["ruby", "sentry"]
      }

      expect(http_tracing.format_query(query)).to eq(
        "token=[Filtered]&page=5&tags[]=ruby&tags[]=sentry"
      )
    end
  end

  describe "#filter_query_params" do
    it "filters sensitive values while preserving parameter names" do
      expect(http_tracing.filter_query_params("token=abc123&page=5")).to eq(
        "token=[Filtered]&page=5"
      )
    end

    it "preserves array query parameters" do
      expect(http_tracing.filter_query_params("foo=bar&baz[]=1&baz[]=2")).to eq(
        "foo=bar&baz[]=1&baz[]=2"
      )
    end

    it "does not collect query params when the mode is off" do
      Sentry.configuration.data_collection.url_query_params.mode = :off

      expect(http_tracing.filter_query_params("token=abc123&page=5")).to be_nil
    end

    it "returns nil for a missing query" do
      expect(http_tracing.filter_query_params(nil)).to be_nil
    end

    it "returns nil when a query cannot be converted to a query string" do
      expect(http_tracing.filter_query_params(Object.new)).to be_nil
    end
  end
end
