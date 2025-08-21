# frozen_string_literal: true

module Sentry
  module Utils
    class SampleRand
      PRECISION = 1_000_000.0
      FORMAT_PRECISION = 6

      attr_reader :trace_id

      def self.valid?(value)
        return false unless value
        value >= 0.0 && value < 1.0
      end

      def self.format(value)
        return unless value

        truncated = (value * PRECISION).floor / PRECISION
        "%.#{FORMAT_PRECISION}f" % truncated
      end

      def initialize(trace_id: nil)
        @trace_id = trace_id
      end

      def generate_from_trace_id
        (random_from_trace_id * PRECISION).floor / PRECISION
      end

      def generate_from_sampling_decision(sampled, sample_rate)
        if invalid_sample_rate?(sample_rate)
          fallback_generation
        else
          generate_based_on_sampling(sampled, sample_rate)
        end
      end

      def generate_from_value(sample_rand_value)
        parsed_value = parse_value(sample_rand_value)

        if self.class.valid?(parsed_value)
          parsed_value
        else
          fallback_generation
        end
      end

      private

      def random_from_trace_id
        if @trace_id
          Random.new(@trace_id[0, 16].to_i(16))
        else
          Random.new
        end.rand(1.0)
      end

      def invalid_sample_rate?(sample_rate)
        sample_rate.nil? || sample_rate <= 0.0 || sample_rate > 1.0
      end

      def fallback_generation
        if @trace_id
          (random_from_trace_id * PRECISION).floor / PRECISION
        else
          format_random(Random.rand(1.0))
        end
      end

      def generate_based_on_sampling(sampled, sample_rate)
        random = random_from_trace_id

        result = if sampled
          random * sample_rate
        elsif sample_rate == 1.0
          random
        else
          sample_rate + random * (1.0 - sample_rate)
        end

        format_random(result)
      end

      def format_random(value)
        truncated = (value * PRECISION).floor / PRECISION
        ("%.#{FORMAT_PRECISION}f" % truncated).to_f
      end

      def parse_value(sample_rand_value)
        Float(sample_rand_value)
      rescue ArgumentError
        nil
      end
    end
  end
end
