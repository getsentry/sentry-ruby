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
    end
  end
end
