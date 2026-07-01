# frozen_string_literal: true

require "json"

module Sentry
  module Utils
    module TelemetryAttributes
      private

      def attribute_hash(raw_value)
        if raw_value.is_a?(Hash) && (raw_value.key?(:value) || raw_value.key?("value"))
          value = raw_value.key?(:value) ? raw_value[:value] : raw_value["value"]
          unit = raw_value.key?(:unit) ? raw_value[:unit] : raw_value["unit"]
        else
          value = raw_value
          unit = nil
        end

        result =
          case value
          when String
            { value: value, type: "string" }
          when TrueClass, FalseClass
            { value: value, type: "boolean" }
          when Integer
            { value: value, type: "integer" }
          when Float
            { value: value, type: "double" }
          else
            begin
              { value: JSON.generate(value), type: "string" }
            rescue
              { value: value, type: "string" }
            end
          end

        result[:unit] = unit.to_s if unit.is_a?(String) || unit.is_a?(Symbol)
        result
      end
    end
  end
end
