# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sentry::Rails::Serializer do
  describe ".serialize" do
    it "recursively serializes hash values" do
      result = described_class.serialize(a: 1, b: { c: 2..3 })

      expect(result).to eq(a: 1, b: { c: [2, 3] })
    end

    it "recursively serializes array elements" do
      result = described_class.serialize([1, [2..3]])

      expect(result).to eq([1, [[2, 3]]])
    end

    it "expands ranges into arrays" do
      expect(described_class.serialize(1..3)).to eq([1, 2, 3])
    end

    context "when the range is beginless" do
      it "stringifies the range instead of expanding it" do
        range = (..10)

        expect(described_class.serialize(range)).to eq(range.to_s)
      end
    end

    context "when the range is endless" do
      it "stringifies the range instead of expanding it" do
        range = (1..)

        expect(described_class.serialize(range)).to eq(range.to_s)
      end
    end

    context "when the range boundary is an ActiveSupport::TimeWithZone" do
      it "stringifies the range instead of expanding it" do
        zone = ActiveSupport::TimeZone["UTC"]
        range = (zone.now - 1.day)...zone.now

        expect(described_class.serialize(range)).to eq(range.to_s)
      end
    end

    it "returns values without a serialization rule unchanged" do
      object = Object.new

      expect(described_class.serialize(object)).to equal(object)
    end
  end
end
