# frozen_string_literal: true

require 'set'
require 'zlib'

module Sentry
  module Metrics
    class SetMetric < Metric
      attr_reader :value

      def initialize(value)
        @value = Set[value.to_f]
      end

      def add(value)
        @value << value
      end

      def serialize
        value.map do |v|
          x.is_a?(String) ? Zlib.crc32(x) : x.to_i
        end
      end

      def weight
        value.size
      end
    end
  end
end
