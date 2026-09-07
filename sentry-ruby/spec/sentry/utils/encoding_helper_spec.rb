# frozen_string_literal: true

RSpec.describe Sentry::Utils::EncodingHelper do
  describe ".encode_to_utf_8" do
    it "returns UTF-8 strings unchanged" do
      value = "hello"
      expect(described_class.encode_to_utf_8(value).encoding).to eq(Encoding::UTF_8)
    end

    it "force-encodes a BINARY string to UTF-8" do
      value = "hello".dup.force_encoding(Encoding::BINARY)
      result = described_class.encode_to_utf_8(value)

      expect(result.encoding).to eq(Encoding::UTF_8)
      expect(result).to eq("hello")
    end

    it "scrubs invalid byte sequences" do
      value = "\xFF\xFEinvalid".dup.force_encoding(Encoding::BINARY)
      result = described_class.encode_to_utf_8(value)

      expect(result.encoding).to eq(Encoding::UTF_8)
      expect(result.valid_encoding?).to eq(true)
    end
  end

  describe ".deep_encode_utf_8" do
    it "recursively encodes strings nested in hashes and arrays" do
      invalid_string = "\xFF\xFEinvalid".dup.force_encoding(Encoding::BINARY)

      value = {
        message: invalid_string,
        list: [invalid_string, { nested: invalid_string }],
        count: 1,
        flag: true,
        untouched: nil
      }

      result = described_class.deep_encode_utf_8(value)

      expect(result[:message].encoding).to eq(Encoding::UTF_8)
      expect(result[:message].valid_encoding?).to eq(true)
      expect(result[:list][0].encoding).to eq(Encoding::UTF_8)
      expect(result[:list][1][:nested].encoding).to eq(Encoding::UTF_8)
      expect(result[:count]).to eq(1)
      expect(result[:flag]).to eq(true)
      expect(result[:untouched]).to be_nil
    end

    it "does not mutate the original structure" do
      invalid_string = "\xFF\xFEinvalid".dup.force_encoding(Encoding::BINARY)
      value = { message: invalid_string }

      described_class.deep_encode_utf_8(value)

      expect(value[:message].encoding).to eq(Encoding::BINARY)
    end

    it "replaces circular references without recursing forever" do
      value = []
      value << value

      result = described_class.deep_encode_utf_8(value)

      expect(result).to eq([nil])
      expect(value.first).to equal(value)
    end
  end
end
