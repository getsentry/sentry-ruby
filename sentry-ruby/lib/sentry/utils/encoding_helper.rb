# frozen_string_literal: true

module Sentry
  module Utils
    module EncodingHelper
      MALFORMED_STRING = "<malformed-string>"

      def self.encode_to_utf_8(value)
        if value.encoding != Encoding::UTF_8 && value.respond_to?(:force_encoding)
          value = value.dup.force_encoding(Encoding::UTF_8)
        end

        value = value.scrub unless value.valid_encoding?
        value
      end

      def self.valid_utf_8?(value)
        return true unless value.respond_to?(:force_encoding)

        value.dup.force_encoding(Encoding::UTF_8).valid_encoding?
      end

      def self.safe_utf_8_string(value)
        valid_utf_8?(value) ? value : MALFORMED_STRING
      end

      # Recursively walks a Hash/Array/String structure and returns a copy
      # with every String forced into valid UTF-8 encoding.
      #
      # Circular Hash and Array references are replaced with nil in the
      # returned copy.
      #
      # @param value [Object]
      # @return [Object]
      def self.deep_encode_utf_8(value, seen = {})
        case value
        when String
          encode_to_utf_8(value)
        when Hash
          return nil if seen.key?(value.object_id)

          seen[value.object_id] = true
          encoded_value = {}

          begin
            value.each do |key, val|
              encoded_key = deep_encode_utf_8(key, seen)
              encoded_value[encoded_key] = deep_encode_utf_8(val, seen)
            end
            encoded_value
          ensure
            seen.delete(value.object_id)
          end
        when Array
          return nil if seen.key?(value.object_id)

          seen[value.object_id] = true
          encoded_value = []

          begin
            value.each do |val|
              encoded_value << deep_encode_utf_8(val, seen)
            end
            encoded_value
          ensure
            seen.delete(value.object_id)
          end
        else
          value
        end
      end
    end
  end
end
