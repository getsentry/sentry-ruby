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
            { value: Utils::EncodingHelper.encode_to_utf_8(value), type: "string" }
          when TrueClass, FalseClass
            { value: value, type: "boolean" }
          when Integer
            { value: value, type: "integer" }
          when Float
            { value: value, type: "double" }
          else
            # `value` may be an arbitrary object (e.g. a Hash/Array) that
            # contains a String with an invalid/non-UTF-8 encoding, which
            # `JSON.generate` raises on as of json 3.0+. Sanitize it before
            # generating rather than reacting to the error.
            begin
              { value: JSON.generate(Utils::EncodingHelper.deep_encode_utf_8(value)), type: "string" }
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
