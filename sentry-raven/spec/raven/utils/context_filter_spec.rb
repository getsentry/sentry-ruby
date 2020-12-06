require "spec_helper"

require "raven/utils/context_filter"

RSpec.describe Raven::Utils::ContextFilter do
  context "filters out ActiveJob keys from context" do
    let(:context) do
      { :_aj_globalid => "gid://app/model/id", :key => "value" }
    end
    let(:expected_context) do
      { "globalid" => "gid://app/model/id", :key => "value" }
    end

    it "removes reserved keys" do
      new_context = described_class.filter_context(context)

      expect(new_context).to eq(expected_context)
    end
  end

  context "filters out ActiveJob keys from nested context" do
    let(:context) do
      {
        :_aj_globalid => "gid://app/model/id",
        :arguments => { :key => "value", :_aj_symbol_keys => ["key"] }
      }
    end
    let(:expected_context) do
      {
        "globalid" => "gid://app/model/id",
        :arguments => { :key => "value", "symbol_keys" => ["key"] }
      }
    end

    it "removes reserved keys" do
      new_context = described_class.filter_context(context)

      expect(new_context).to eq(expected_context)
    end
  end
end
