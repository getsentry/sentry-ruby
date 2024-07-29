# frozen_string_literal: true

RSpec.describe Sentry::Breadcrumb do
  let(:stringio) { StringIO.new }

  before do
    perform_basic_setup do |config|
      config.sdk_logger = ::Logger.new(stringio)
    end
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

    it "sets the level to warning if warn" do
      crumb = described_class.new(level: "warn")
      expect(crumb.level).to eq("warning")
    end
  end

  describe "#message=" do
    it "limits the maximum size of message" do
      long_message = "a" * Sentry::Event::MAX_MESSAGE_SIZE_IN_BYTES * 2

      crumb = described_class.new
      crumb.message = long_message
      expect(crumb.message.length).to eq(Sentry::Event::MAX_MESSAGE_SIZE_IN_BYTES + 1)
    end

    it "removes bad encoding message gracefully" do
      crumb = described_class.new
      crumb.message = "foo \x1F\xE6"
      expect(crumb.message).to eq("")
    end
  end

  describe "#level=" do
    it "sets the level" do
      crumb = described_class.new
      crumb.level = "error"
      expect(crumb.level).to eq("error")
    end

    it "sets the level to warning if warn" do
      crumb = described_class.new
      crumb.level = "warn"
      expect(crumb.level).to eq("warning")
    end
  end

  describe "#to_h" do
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

    let(:very_deep_crumb) do
      data = [[[[[ { a: [{ b: [[{ c: 4 }]] }] }]]]]]

      Sentry::Breadcrumb.new(
        category: "cow",
        message: "I cause too much recursion",
        data: data
      )
    end

    it "serializes data correctly" do
      result = crumb.to_h

      expect(result[:category]).to eq("foo")
      expect(result[:message]).to eq("crumb")
      expect(result[:data]).to eq({ "name" => "John", "age" => 25 })
    end

    it "rescues data serialization issue and ditch the data" do
      result = problematic_crumb.to_h

      expect(result[:category]).to eq("baz")
      expect(result[:message]).to eq("I cause issues")
      expect(result[:data][:error]).to eq("[data were removed due to serialization issues]")
      expect(stringio.string).to match(/can't serialize breadcrumb data because of error: nesting of 10 is too deep/)
    end

    it "rescues data serialization issue for extremely nested data and ditch the data" do
      result = very_deep_crumb.to_hash

      expect(result[:category]).to eq("cow")
      expect(result[:message]).to eq("I cause too much recursion")
      expect(result[:data][:error]).to eq("[data were removed due to serialization issues]")
      expect(stringio.string).to match(/can't serialize breadcrumb data because of error: nesting of 10 is too deep/)
    end
  end
end
