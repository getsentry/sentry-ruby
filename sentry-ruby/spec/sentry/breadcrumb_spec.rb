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

  describe "#initialize" do
    it "limits the maximum size of message" do
      long_message = "a" * Sentry::Event::MAX_MESSAGE_SIZE_IN_BYTES * 2

      crumb = described_class.new(message: long_message)
      expect(crumb.message.length).to eq(Sentry::Event::MAX_MESSAGE_SIZE_IN_BYTES + 1)
    end
  end

  describe "#message=" do
    it "limits the maximum size of message" do
      long_message = "a" * Sentry::Event::MAX_MESSAGE_SIZE_IN_BYTES * 2

      crumb = described_class.new
      crumb.message = long_message
      expect(crumb.message.length).to eq(Sentry::Event::MAX_MESSAGE_SIZE_IN_BYTES + 1)
    end
  end

  describe "#to_hash" do
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
