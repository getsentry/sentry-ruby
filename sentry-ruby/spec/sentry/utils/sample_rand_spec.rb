# frozen_string_literal: true

RSpec.describe Sentry::Utils::SampleRand do
  describe ".generate_from_trace_id" do
    it "generates a float in range [0, 1) with 6 decimal places" do
      trace_id = "abcdef1234567890abcdef1234567890"
      sample_rand = described_class.generate_from_trace_id(trace_id)

      expect(sample_rand).to be_a(Float)
      expect(sample_rand).to be >= 0.0
      expect(sample_rand).to be < 1.0
      expect(sample_rand.to_s.split('.')[1].length).to be <= 6
    end

    it "generates deterministic values for the same trace_id" do
      trace_id = "abcdef1234567890abcdef1234567890"

      sample_rand1 = described_class.generate_from_trace_id(trace_id)
      sample_rand2 = described_class.generate_from_trace_id(trace_id)

      expect(sample_rand1).to eq(sample_rand2)
    end

    it "generates different values for different trace_ids" do
      trace_id1 = "abcdef1234567890abcdef1234567890"
      trace_id2 = "fedcba0987654321fedcba0987654321"

      sample_rand1 = described_class.generate_from_trace_id(trace_id1)
      sample_rand2 = described_class.generate_from_trace_id(trace_id2)

      expect(sample_rand1).not_to eq(sample_rand2)
    end

    it "handles short trace_ids" do
      trace_id = "abc123"
      sample_rand = described_class.generate_from_trace_id(trace_id)

      expect(sample_rand).to be_a(Float)
      expect(sample_rand).to be >= 0.0
      expect(sample_rand).to be < 1.0
    end
  end

  describe ".generate_from_sampling_decision" do
    let(:trace_id) { "abcdef1234567890abcdef1234567890" }

    context "with valid sample_rate and sampled=true" do
      it "generates value in range [0, sample_rate)" do
        sample_rate = 0.5
        sample_rand = described_class.generate_from_sampling_decision(true, sample_rate, trace_id)

        expect(sample_rand).to be >= 0.0
        expect(sample_rand).to be < sample_rate
      end

      it "is deterministic with trace_id" do
        sample_rate = 0.5

        sample_rand1 = described_class.generate_from_sampling_decision(true, sample_rate, trace_id)
        sample_rand2 = described_class.generate_from_sampling_decision(true, sample_rate, trace_id)

        expect(sample_rand1).to eq(sample_rand2)
      end
    end

    context "with valid sample_rate and sampled=false" do
      it "generates value in range [sample_rate, 1)" do
        sample_rate = 0.3
        sample_rand = described_class.generate_from_sampling_decision(false, sample_rate, trace_id)

        expect(sample_rand).to be >= sample_rate
        expect(sample_rand).to be < 1.0
      end

      it "is deterministic with trace_id" do
        sample_rate = 0.3

        sample_rand1 = described_class.generate_from_sampling_decision(false, sample_rate, trace_id)
        sample_rand2 = described_class.generate_from_sampling_decision(false, sample_rate, trace_id)

        expect(sample_rand1).to eq(sample_rand2)
      end
    end

    context "with invalid sample_rate" do
      it "falls back to trace_id generation when sample_rate is nil" do
        expected = described_class.generate_from_trace_id(trace_id)
        actual = described_class.generate_from_sampling_decision(true, nil, trace_id)

        expect(actual).to eq(expected)
      end

      it "falls back to trace_id generation when sample_rate is 0" do
        expected = described_class.generate_from_trace_id(trace_id)
        actual = described_class.generate_from_sampling_decision(true, 0.0, trace_id)

        expect(actual).to eq(expected)
      end

      it "falls back to trace_id generation when sample_rate > 1" do
        expected = described_class.generate_from_trace_id(trace_id)
        actual = described_class.generate_from_sampling_decision(true, 1.5, trace_id)

        expect(actual).to eq(expected)
      end

      it "uses Random.rand when no trace_id provided" do
        allow(Random).to receive(:rand).and_return(0.123456)

        result = described_class.generate_from_sampling_decision(true, nil, nil)

        expect(result).to eq(0.123456)
      end
    end
  end

  describe ".valid?" do
    it "returns true for valid float values" do
      expect(described_class.valid?(0.0)).to be true
      expect(described_class.valid?(0.5)).to be true
      expect(described_class.valid?(0.999999)).to be true
    end

    it "returns true for valid string values" do
      expect(described_class.valid?("0.0")).to be true
      expect(described_class.valid?("0.5")).to be true
      expect(described_class.valid?("0.999999")).to be true
    end

    it "returns false for invalid values" do
      expect(described_class.valid?(nil)).to be false
      expect(described_class.valid?(-0.1)).to be false
      expect(described_class.valid?(1.0)).to be false
      expect(described_class.valid?(1.5)).to be false
      expect(described_class.valid?("")).to be false
      # Note: "invalid" string converts to 0.0 which is valid
    end
  end

  describe ".format" do
    it "formats float to 6 decimal places" do
      expect(described_class.format(0.123456789)).to eq("0.123456")
      expect(described_class.format(0.1)).to eq("0.100000")
      expect(described_class.format(0.0)).to eq("0.000000")
    end
  end
end
