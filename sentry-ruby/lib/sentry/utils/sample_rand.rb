# frozen_string_literal: true

module Sentry
  module Utils
    module SampleRand
      def self.generate_from_trace_id(trace_id)
        seed = trace_id[0, 16].to_i(16)
        rng = Random.new(seed)

        value = rng.rand

        (value * 1_000_000).floor / 1_000_000.0
      end

      def self.generate_from_sampling_decision(sampled, sample_rate, trace_id = nil)
        if sample_rate.nil? || sample_rate <= 0.0 || sample_rate > 1.0
          return trace_id ? generate_from_trace_id(trace_id) : Random.rand.round(6)
        end

        rng = trace_id ? Random.new(trace_id[0, 16].to_i(16)) : Random

        if sampled
          (rng.rand * sample_rate).round(6)
        else
          (sample_rate + rng.rand * (1.0 - sample_rate)).round(6)
        end
      end

      def self.valid?(sample_rand)
        return false unless sample_rand
        return false if sample_rand.is_a?(String) && sample_rand.empty?

        value = sample_rand.is_a?(String) ? sample_rand.to_f : sample_rand
        value >= 0.0 && value < 1.0
      end

      def self.format(sample_rand)
        truncated = (sample_rand * 1_000_000).floor / 1_000_000.0
        "%.6f" % truncated
      end
    end
  end
end
