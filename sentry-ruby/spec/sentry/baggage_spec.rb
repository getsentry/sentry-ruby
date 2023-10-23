require "spec_helper"

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
end
