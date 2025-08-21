# frozen_string_literal: true

RSpec.describe Sentry::Utils::SampleRand do
  describe "#generate_from_trace_id" do
    it "generates a float in range [0, 1) with 6 decimal places" do
      trace_id = "abcdef1234567890abcdef1234567890"
      generator = described_class.new(trace_id: trace_id)
      sample_rand = generator.generate_from_trace_id

      expect(sample_rand).to be_a(Float)
      expect(sample_rand).to be >= 0.0
      expect(sample_rand).to be < 1.0
      expect(sample_rand.to_s.split('.')[1].length).to be <= 6
    end

    it "generates deterministic values for the same trace_id" do
      trace_id = "abcdef1234567890abcdef1234567890"

      generator1 = described_class.new(trace_id: trace_id)
      generator2 = described_class.new(trace_id: trace_id)
      sample_rand1 = generator1.generate_from_trace_id
      sample_rand2 = generator2.generate_from_trace_id

      expect(sample_rand1).to eq(sample_rand2)
    end

    it "generates different values for different trace_ids" do
      trace_id1 = "abcdef1234567890abcdef1234567890"
      trace_id2 = "fedcba0987654321fedcba0987654321"

      generator1 = described_class.new(trace_id: trace_id1)
      generator2 = described_class.new(trace_id: trace_id2)
      sample_rand1 = generator1.generate_from_trace_id
      sample_rand2 = generator2.generate_from_trace_id

      expect(sample_rand1).not_to eq(sample_rand2)
    end

    it "handles short trace_ids" do
      trace_id = "abc123"
      generator = described_class.new(trace_id: trace_id)
      sample_rand = generator.generate_from_trace_id

      expect(sample_rand).to be_a(Float)
      expect(sample_rand).to be >= 0.0
      expect(sample_rand).to be < 1.0
    end
  end

  describe "#generate_from_sampling_decision" do
    let(:trace_id) { "abcdef1234567890abcdef1234567890" }

    context "with valid sample_rate and sampled=true" do
      it "generates value in range [0, sample_rate)" do
        sample_rate = 0.5
        generator = described_class.new(trace_id: trace_id)
        sample_rand = generator.generate_from_sampling_decision(true, sample_rate)

        expect(sample_rand).to be >= 0.0
        expect(sample_rand).to be < sample_rate
      end

      it "is deterministic with trace_id" do
        sample_rate = 0.5

        generator1 = described_class.new(trace_id: trace_id)
        generator2 = described_class.new(trace_id: trace_id)
        sample_rand1 = generator1.generate_from_sampling_decision(true, sample_rate)
        sample_rand2 = generator2.generate_from_sampling_decision(true, sample_rate)

        expect(sample_rand1).to eq(sample_rand2)
      end

      it "never generates invalid values even with sample_rate = 1.0" do
        generator = described_class.new(trace_id: trace_id)
        result = generator.generate_from_sampling_decision(true, 1.0)

        expect(result).to be >= 0.0
        expect(result).to be < 1.0
        expect(described_class.valid?(result)).to be true
      end
    end

    context "with valid sample_rate and sampled=false" do
      it "generates value in range [sample_rate, 1)" do
        sample_rate = 0.3
        generator = described_class.new(trace_id: trace_id)
        sample_rand = generator.generate_from_sampling_decision(false, sample_rate)

        expect(sample_rand).to be >= sample_rate
        expect(sample_rand).to be < 1.0
      end

      it "is deterministic with trace_id" do
        sample_rate = 0.3

        generator1 = described_class.new(trace_id: trace_id)
        generator2 = described_class.new(trace_id: trace_id)
        sample_rand1 = generator1.generate_from_sampling_decision(false, sample_rate)
        sample_rand2 = generator2.generate_from_sampling_decision(false, sample_rate)

        expect(sample_rand1).to eq(sample_rand2)
      end
    end

    context "with invalid sample_rate" do
      it "falls back to trace_id generation when sample_rate is nil" do
        generator1 = described_class.new(trace_id: trace_id)
        generator2 = described_class.new(trace_id: trace_id)
        expected = generator1.generate_from_trace_id
        actual = generator2.generate_from_sampling_decision(true, nil)

        expect(actual).to eq(expected)
      end

      it "falls back to trace_id generation when sample_rate is 0" do
        generator1 = described_class.new(trace_id: trace_id)
        generator2 = described_class.new(trace_id: trace_id)
        expected = generator1.generate_from_trace_id
        actual = generator2.generate_from_sampling_decision(true, 0.0)

        expect(actual).to eq(expected)
      end

      it "falls back to trace_id generation when sample_rate > 1" do
        generator1 = described_class.new(trace_id: trace_id)
        generator2 = described_class.new(trace_id: trace_id)
        expected = generator1.generate_from_trace_id
        actual = generator2.generate_from_sampling_decision(true, 1.5)

        expect(actual).to eq(expected)
      end

      it "uses Random.rand when no trace_id provided" do
        generator = described_class.new
        result = generator.generate_from_sampling_decision(true, nil)

        expect(result).to be_a(Float)
        expect(result).to be >= 0.0
        expect(result).to be < 1.0
        expect(result.to_s.split('.')[1].length).to be <= 6
      end

      it "never generates values >= 1.0 even with edge case rounding" do
        1000.times do
          generator = described_class.new
          result = generator.generate_from_sampling_decision(true, nil)
          expect(result).to be < 1.0
        end
      end

      it "handles edge case where sampled is false and sample_rate is 1.0" do
        generator = described_class.new(trace_id: "abcdef1234567890abcdef1234567890")
        result = generator.generate_from_sampling_decision(false, 1.0)

        expect(result).to be_a(Float)
        expect(result).to be >= 0.0
        expect(result).to be < 1.0
        expect(described_class.valid?(result)).to be true
      end
    end
  end

  describe "#generate_from_value" do
    it "accepts valid float values" do
      generator = described_class.new
      result = generator.generate_from_value(0.5)
      expect(described_class.valid?(result)).to be true
      expect(result).to eq(0.5)
    end

    it "accepts valid string values" do
      generator = described_class.new
      result = generator.generate_from_value("0.5")
      expect(described_class.valid?(result)).to be true
      expect(result).to eq(0.5)
    end

    it "falls back for invalid values" do
      generator = described_class.new(trace_id: "abcdef1234567890abcdef1234567890")
      result = generator.generate_from_value(1.5)
      expect(described_class.valid?(result)).to be true
      expect(result).to be >= 0.0
      expect(result).to be < 1.0
    end
  end

  describe ".valid?" do
    it "returns true for valid values" do
      expect(described_class.valid?(0.5)).to be true
    end

    it "returns false for invalid values" do
      expect(described_class.valid?(1.5)).to be false
    end
  end

  describe "#generate_from_value with invalid string inputs" do
    it "rejects non-numeric strings that convert to 0.0" do
      generator = described_class.new(trace_id: "abcdef1234567890abcdef1234567890")

      invalid_strings = ["invalid", "abc", "not_a_number", ""]

      invalid_strings.each do |invalid_string|
        result = generator.generate_from_value(invalid_string)

        expect(result).not_to eq(0.0)
        expect(described_class.valid?(result)).to be true
        expect(result).to be >= 0.0
        expect(result).to be < 1.0
      end
    end

    it "accepts valid numeric strings" do
      generator = described_class.new

      valid_strings = ["0.5", "0.0", "0.999999", "0", "0.000000"]

      valid_strings.each do |valid_string|
        result = generator.generate_from_value(valid_string)
        expect(result).to eq(valid_string.to_f)
        expect(described_class.valid?(result)).to be true
      end
    end

    it "rejects numeric strings that are out of valid range" do
      generator = described_class.new(trace_id: "abcdef1234567890abcdef1234567890")

      invalid_range_strings = ["1.0", "1.5", "-0.1", "-1.0"]

      invalid_range_strings.each do |invalid_string|
        result = generator.generate_from_value(invalid_string)

        expect(result).not_to eq(invalid_string.to_f)
        expect(described_class.valid?(result)).to be true
        expect(result).to be >= 0.0
        expect(result).to be < 1.0
      end
    end

    ["0.5abc", "abc0.5", "0..5", "0.5.0", "0.5e2", ".", "-"].each do |value|
      it "rejects #{value.inspect} and generates from trace_id" do
        generator = described_class.new(trace_id: "abcdef1234567890abcdef1234567890")

        result = generator.generate_from_value(value)

        expect(result).not_to eq(value.to_f)
        expect(described_class.valid?(result)).to be true
        expect(result).to be >= 0.0
        expect(result).to be < 1.0
      end
    end
  end

  describe ".format" do
    it "formats float to 6 decimal places" do
      expect(described_class.format(0.123456789)).to eq("0.123456")
      expect(described_class.format(0.9999999)).to eq("0.999999")
      expect(described_class.format(0.1)).to eq("0.100000")
      expect(described_class.format(0.0)).to eq("0.000000")
    end
  end
end
