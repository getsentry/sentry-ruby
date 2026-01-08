# frozen_string_literal: true

require "json"

module Sentry
  module Utils
    module TelemetryAttributes
      private

      def attribute_hash(value)
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
      end
    end
  end
end
