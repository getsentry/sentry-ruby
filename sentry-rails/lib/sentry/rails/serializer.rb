# frozen_string_literal: true

module Sentry
  module Rails
    module Serializer
      def self.serialize(value)
        case value
        when Range
          serialize_range(value)
        when Hash
          value.transform_values { |item| serialize(item) }
        when Array, Enumerable
          value.map { |item| serialize(item) }
        when ->(item) { item.respond_to?(:to_global_id) }
          serialize_global_id(value)
        else
          value
        end
      end

      def self.serialize_global_id(value)
        value.to_global_id.to_s
      rescue StandardError
        value
      end

      def self.serialize_range(range)
        return range.to_s if range.begin.nil? || range.end.nil?
        return range.to_s if range.begin.is_a?(::ActiveSupport::TimeWithZone)

        range.map { |item| serialize(item) }
      end
    end
  end
end
