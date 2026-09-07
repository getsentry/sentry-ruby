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

    it "returns the sanitized data" do
      result = crumb.to_h

      expect(result[:category]).to eq("foo")
      expect(result[:message]).to eq("crumb")
      expect(result[:data]).to eq({ name: "John", age: 25 })
    end

    it "handles a circular breadcrumb without recursing forever" do
      result = problematic_crumb.to_h

      expect(result[:category]).to eq("baz")
      expect(result[:message]).to eq("I cause issues")
      expect(result[:data]).to eq([[nil]])
      expect { JSON.generate(result[:data]) }.not_to raise_error
    end

    it "sanitizes non-UTF-8 encoded strings in data at assignment time (json 3.0+ behavior)" do
      # json 3.0+ raises Encoding::UndefinedConversionError instead of just
      # warning when JSON.generate encounters a String tagged with a
      # non-UTF-8 encoding that contains bytes invalid for the target
      # encoding. Breadcrumb#data= sanitizes proactively so this never
      # reaches JSON.generate in the first place.
      invalid_string = "\xFF\xFEinvalid".dup.force_encoding(Encoding::BINARY)
      crumb = Sentry::Breadcrumb.new(category: "foo", message: "crumb", data: { note: invalid_string })

      expect(crumb.data[:note].encoding).to eq(Encoding::UTF_8)
      expect(crumb.data[:note].valid_encoding?).to eq(true)

      result = crumb.to_h
      expect(result[:data][:note].encoding).to eq(Encoding::UTF_8)
      expect(result[:data][:note].valid_encoding?).to eq(true)
    end
  end
end
