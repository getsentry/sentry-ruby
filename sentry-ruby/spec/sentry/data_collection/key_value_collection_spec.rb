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

      it "normalizes terms assigned after initialization" do
        collection.terms = ["USER"]

        expect(collection.filter("user_id" => "1")).to eq("user_id" => "[Filtered]")
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
