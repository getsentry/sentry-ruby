# frozen_string_literal: true

RSpec.describe Sentry::Baggage do
  let(:malformed_baggage) { "," }
  let(:third_party_baggage) { "other-vendor-value-1=foo;bar;baz, other-vendor-value-2=foo;bar;" }

  let(:mixed_baggage) do
    "other-vendor-value-1=foo;bar;baz, "\
    "sentry-trace_id=771a43a4192642f0b136d5159a501700, "\
    "sentry-public_key=49d0f7386ad645858ae85020e393bef3, "\
    "sentry-sample_rate=0.01337, "\
    "sentry-user_id=Am%C3%A9lie, "\
    "sentry-foo=bar, "\
    "other-vendor-value-2=foo;bar;"
  end

  describe "#dynamic_sampling_context" do
    context "when malformed baggage" do
      it "is empty" do
        baggage = described_class.from_incoming_header(malformed_baggage)
        expect(baggage.dynamic_sampling_context).to eq({})
      end
    end

    context "when only third party baggage" do
      it "is empty" do
        baggage = described_class.from_incoming_header(third_party_baggage)
        expect(baggage.dynamic_sampling_context).to eq({})
      end
    end

    context "when mixed baggage" do
      it "populates DSC" do
        baggage = described_class.from_incoming_header(mixed_baggage)

        expect(baggage.dynamic_sampling_context).to eq({
          "sample_rate" => "0.01337",
          "public_key" => "49d0f7386ad645858ae85020e393bef3",
          "trace_id" => "771a43a4192642f0b136d5159a501700",
          "user_id" => "Amélie",
          "foo" => "bar"
        })
      end
    end
  end

  describe "#serialize" do
    context "default args (without third party)" do
      context "when malformed baggage" do
        it "is empty string" do
          baggage = described_class.from_incoming_header(malformed_baggage)
          expect(baggage.serialize).to eq("")
        end
      end

      context "when only third party baggage" do
        it "is empty" do
          baggage = described_class.from_incoming_header(third_party_baggage)
          expect(baggage.serialize).to eq("")
        end
      end

      context "when mixed baggage" do
        it "populates DSC" do
          baggage = described_class.from_incoming_header(mixed_baggage)

          expect(baggage.serialize).to eq(
            "sentry-trace_id=771a43a4192642f0b136d5159a501700,"\
            "sentry-public_key=49d0f7386ad645858ae85020e393bef3,"\
            "sentry-sample_rate=0.01337,"\
            "sentry-user_id=Am%C3%A9lie,"\
            "sentry-foo=bar"
          )
        end
      end
    end
  end

  describe "#mutable" do
    context "when only third party baggage" do
      it "is mutable" do
        baggage = described_class.from_incoming_header(third_party_baggage)
        expect(baggage.mutable).to eq(true)
      end
    end

    context "when has sentry baggage" do
      it "is immutable" do
        baggage = described_class.from_incoming_header(mixed_baggage)
        expect(baggage.mutable).to eq(false)
      end
    end
  end

  describe "#freeze!" do
    it "makes it immutable" do
      baggage = described_class.from_incoming_header(third_party_baggage)
      expect(baggage.mutable).to eq(true)
      baggage.freeze!
      expect(baggage.mutable).to eq(false)
    end
  end

  describe ".serialize_with_third_party" do
    let(:sentry_items) do
      {
        "trace_id" => "771a43a4192642f0b136d5159a501700",
        "public_key" => "49d0f7386ad645858ae85020e393bef3",
        "sample_rate" => "0.01337"
      }
    end

    context "when combined baggage is within limits" do
      it "includes both sentry and third-party items unchanged" do
        third_party_header = "routingKey=myvalue,tenantId=123"
        result = described_class.serialize_with_third_party(sentry_items, third_party_header)

        expect(result).to include("sentry-trace_id=771a43a4192642f0b136d5159a501700")
        expect(result).to include("sentry-public_key=49d0f7386ad645858ae85020e393bef3")
        expect(result).to include("sentry-sample_rate=0.01337")
        expect(result).to include("routingKey=myvalue")
        expect(result).to include("tenantId=123")
      end
    end

    context "when exceeding MAX_MEMBER_COUNT (64)" do
      it "drops third-party items first" do
        # Create 10 sentry items
        many_sentry_items = (0...10).each_with_object({}) do |i, hash|
          hash["key#{i}"] = "value#{i}"
        end

        # Create 60 third-party items (total would be 70, exceeds 64)
        third_party_items = (0...60).map { |i| "third#{i}=val#{i}" }.join(",")

        result = described_class.serialize_with_third_party(many_sentry_items, third_party_items)

        # All 10 sentry items should be present
        (0...10).each do |i|
          expect(result).to include("sentry-key#{i}=value#{i}")
        end

        # Count total items (should be 64 max)
        total_items = result.split(",").size
        expect(total_items).to be <= 64

        # Some third-party items should be dropped
        third_party_count = result.split(",").count { |item| item.start_with?("third") }
        expect(third_party_count).to be < 60
      end
    end

    context "when exceeding MAX_BAGGAGE_BYTES (8192)" do
      it "drops third-party items first" do
        # Create sentry items that are ~2KB
        large_sentry_items = (0...5).each_with_object({}) do |i, hash|
          hash["key#{i}"] = "x" * 350
        end

        # Create third-party items that would push us over 8192 bytes
        large_third_party = (0...20).map { |i| "third#{i}=#{'y' * 350}" }.join(",")

        result = described_class.serialize_with_third_party(large_sentry_items, large_third_party)

        # All sentry items should be present
        (0...5).each do |i|
          expect(result).to include("sentry-key#{i}=")
        end

        # Total size should not exceed 8192 bytes
        expect(result.bytesize).to be <= 8192

        # Some third-party items should be dropped
        third_party_count = result.split(",").count { |item| item.start_with?("third") }
        expect(third_party_count).to be < 20
      end
    end

    context "when sentry items alone exceed limits" do
      it "drops sentry items to fit within limits" do
        # Create 70 sentry items (exceeds 64)
        many_sentry_items = (0...70).each_with_object({}) do |i, hash|
          hash["key#{i}"] = "value#{i}"
        end

        result = described_class.serialize_with_third_party(many_sentry_items, nil)

        # Should have exactly 64 items
        total_items = result.split(",").size
        expect(total_items).to eq(64)
      end

      it "drops sentry items to fit within byte limit" do
        # Create sentry items that exceed 8192 bytes
        large_sentry_items = (0...30).each_with_object({}) do |i, hash|
          hash["key#{i}"] = "x" * 400
        end

        result = described_class.serialize_with_third_party(large_sentry_items, nil)

        # Should not exceed byte limit
        expect(result.bytesize).to be <= 8192

        # Should have dropped some items
        total_items = result.split(",").size
        expect(total_items).to be < 30
      end
    end

    context "when third_party_header is nil or empty" do
      it "handles nil third-party header" do
        result = described_class.serialize_with_third_party(sentry_items, nil)

        expect(result).to include("sentry-trace_id=771a43a4192642f0b136d5159a501700")
        expect(result).to include("sentry-public_key=49d0f7386ad645858ae85020e393bef3")
        expect(result).to include("sentry-sample_rate=0.01337")
      end

      it "handles empty third-party header" do
        result = described_class.serialize_with_third_party(sentry_items, "")

        expect(result).to include("sentry-trace_id=771a43a4192642f0b136d5159a501700")
        expect(result).to include("sentry-public_key=49d0f7386ad645858ae85020e393bef3")
        expect(result).to include("sentry-sample_rate=0.01337")
      end
    end
  end
end
