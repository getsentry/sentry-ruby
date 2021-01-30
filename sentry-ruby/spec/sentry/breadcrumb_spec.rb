require "spec_helper"

RSpec.describe Sentry::Breadcrumb do
  before do
    perform_basic_setup
  end

  let(:crumb) do
    Sentry::Breadcrumb.new(
      category: "foo",
      message: "crumb",
      data: {
        name: "John",
        age: 25
      }
    )
  end

  let(:problematic_crumb) do
    # circular reference
    a = []
    b = []
    a.push(b)
    b.push(a)

    Sentry::Breadcrumb.new(
      category: "baz",
      message: "I cause issues",
      data: a
    )
  end

  describe "#to_hash" do
    it "serializes data correctly" do
      result = crumb.to_hash

      expect(result[:category]).to eq("foo")
      expect(result[:message]).to eq("crumb")
      expect(result[:data]).to eq({ "name" => "John", "age" => 25 })
    end

    it "rescues data serialization issue and ditch the data" do
      result = problematic_crumb.to_hash

      expect(result[:category]).to eq("baz")
      expect(result[:message]).to eq("I cause issues")
      expect(result[:data]).to eq("[data were removed due to serialization issues]")
    end
  end
end
