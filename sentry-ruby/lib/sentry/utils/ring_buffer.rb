# frozen_string_literal: true

require "sentry/core_ext/object/deep_dup"

module Sentry
  module Utils
    class RingBuffer
      attr_reader :values

      def initialize(capacity)
        raise ArgumentError, "capacity must be positive" unless capacity.positive?

        @capacity = capacity
        @values = {}
      end

      def set(key, value)
        @values.delete(key)
        @values[key] = value
        @values.shift if @values.size > @capacity
      end

      def clear
        @values.clear
      end

      def empty?
        @values.empty?
      end

      def dup
        copy = self.class.new(@capacity)
        copy.values.merge!(@values)
        copy
      end
    end
  end
end
