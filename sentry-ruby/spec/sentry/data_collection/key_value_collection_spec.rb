# frozen_string_literal: true

require "sentry/data_collection/key_value_collection"

RSpec.describe Sentry::DataCollection::KeyValueCollection do
  subject(:collection) { described_class.new(mode: mode, terms: terms) }

  let(:values) do
    {
      "Authorization" => "secret-token",
      "page" => "2",
      "display_name" => "Ada",
      42 => "numeric key"
    }
  end
  let(:mode) { :deny_list }
  let(:terms) { nil }

  describe ".from" do
    it "maps true to deny-list mode" do
      expect(described_class.from(true).mode).to eq(:deny_list)
    end

    it "maps false to off mode" do
      expect(described_class.from(false).mode).to eq(:off)
    end

    it "returns an existing collection unchanged" do
      expect(described_class.from(collection)).to be(collection)
    end
  end

  describe "#mode=" do
    it "maps true to deny-list mode" do
      collection.mode = true

      expect(collection.mode).to eq(:deny_list)
    end

    it "maps false to off mode" do
      collection.mode = false

      expect(collection.mode).to eq(:off)
    end
  end

  describe "#filter" do
    it "uses the collection configuration" do
      expect(collection.filter(values)).to eq(
        "Authorization" => "[Filtered]",
        "page" => "2",
        "display_name" => "Ada",
        42 => "numeric key"
      )
    end

    context "when mode is :off" do
      let(:mode) { :off }

      it "does not collect keys or values" do
        expect(collection.filter(values)).to eq({})
      end
    end

    context "when mode is :deny_list" do
      it "matches sensitive terms partially and case-insensitively" do
        expect(described_class.new(mode: :deny_list, terms: nil).filter(
          { "X-Auth-Token" => "a", "ACCESS_SECRET_VALUE" => "b", "random_field" => "c" }
        )).to eq(
          "X-Auth-Token" => "[Filtered]",
          "ACCESS_SECRET_VALUE" => "[Filtered]",
          "random_field" => "c"
        )
      end

      it "applies additional deny terms" do
        expect(described_class.new(mode: :deny_list, terms: ["USER", :internal]).filter(
          { "user_id" => "1", "internal" => "value" }
        )).to eq(
          "user_id" => "[Filtered]",
          "internal" => "[Filtered]"
        )
      end

      it "matches regular expression terms" do
        expect(described_class.new(mode: :deny_list, terms: [/private[-_]data/]).filter(
          { "private_data" => "secret", "PRIVATE_DATA" => "visible", "public_data" => "visible" }
        )).to eq(
          "private_data" => "[Filtered]",
          "PRIVATE_DATA" => "visible",
          "public_data" => "visible"
        )
      end

      it "preserves regular expression terms when assigning terms" do
        regexp = /private/i
        collection.terms = [regexp]

        expect(collection.terms).to eq([regexp])
      end

      it "normalizes terms assigned after initialization" do
        collection.terms = ["USER"]

        expect(collection.filter({ "user_id" => "1" })).to eq("user_id" => "[Filtered]")
      end

      it "covers every built-in sensitive term (case insensitive) and leaves other keys unchanged" do
        sensitive_values = Sentry::DataCollection::KeyValueCollection::SENSITIVE_DENY_LIST.flat_map do |term|
          [
            ["prefix-#{term}-suffix", "value"],
            ["prefix-#{term.upcase}-suffix", "value"]
          ]
        end.to_h

        values = sensitive_values.merge("page" => "2", "display_name" => "Ada")

        expect(collection.filter(values)).to eq(
          sensitive_values.transform_values { "[Filtered]" }.merge(
            "page" => "2",
            "display_name" => "Ada"
          )
        )
      end
    end

    context "when mode is :allow_list" do
      let(:mode) { :allow_list }
      let(:terms) { ["page", "display"] }

      it "filters values whose keys are not allowed" do
        expect(collection.filter(values)).to eq(
          "Authorization" => "[Filtered]",
          "page" => "2",
          "display_name" => "Ada",
          42 => "[Filtered]"
        )
      end

      it "still filters sensitive keys listed in the allow list" do
        expect(described_class.new(mode: :allow_list, terms: ["token", "public"]).filter(
          { "token" => "secret", "public" => "value" }
        )).to eq("token" => "[Filtered]", "public" => "value")
      end

      it "does not allow every key when terms include nil or blank values" do
        expect(described_class.new(mode: :allow_list, terms: [nil, "", "  "]).filter(
          { "public" => "value", "page" => "2" }
        )).to eq("public" => "[Filtered]", "page" => "[Filtered]")
      end
    end

    it "does not mutate the input" do
      original = values.dup
      collection.filter(values)

      expect(values).to eq(original)
    end
  end
end
