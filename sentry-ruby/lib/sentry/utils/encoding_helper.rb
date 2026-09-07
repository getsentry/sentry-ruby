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
      # This is needed because `JSON.generate`/`JSON.dump` on json 3.0+ raise
      # an `Encoding::UndefinedConversionError` (previously just a
      # deprecation warning on json 2.8+) when they encounter a String
      # tagged with a non-UTF-8 encoding (e.g. `ASCII-8BIT`/`BINARY`) that
      # contains bytes invalid for the target encoding. Use this to sanitize
      # payloads before handing them to the JSON generator.
      #
      # @param value [Object]
      # @return [Object]
      def self.deep_encode_utf_8(value)
        case value
        when String
          encode_to_utf_8(value)
        when Hash
          value.each_with_object({}) do |(key, val), memo|
            memo[deep_encode_utf_8(key)] = deep_encode_utf_8(val)
          end
        when Array
          value.map { |val| deep_encode_utf_8(val) }
        else
          value
        end
      end
    end
  end
end
