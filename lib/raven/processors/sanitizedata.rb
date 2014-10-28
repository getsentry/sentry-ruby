require 'raven/processor'
require 'json'

module Raven
  module Processor
    class SanitizeData < Processor

      STRING_MASK = '********'
      INT_MASK = 0
      FIELDS_RE = /(authorization|password|passwd|secret|ssn|social(.*)?sec)/i
      VALUES_RE = /^\d{16}$/

      def apply(value, key = nil, visited = [], &block)
        if value.is_a?(Hash)
          return "{...}" if visited.include?(value.__id__)
          visited += [value.__id__]

          value.each.reduce({}) do |memo, (k, v)|
            memo[k] = apply(v, k, visited, &block)
            memo
          end
        elsif value.is_a?(Array)
          return "[...]" if visited.include?(value.__id__)
          visited += [value.__id__]

          value.map do |value_|
            apply(value_, key, visited, &block)
          end
        elsif value.is_a?(String) && json_hash = parse_json_or_nil(value)
          return "[...]" if visited.include?(value.__id__)
          visited += [value.__id__]

          json_hash = json_hash.each.reduce({}) do |memo, (k, v)|
            memo[k] = apply(v, k, visited, &block)
            memo
          end

          json_hash.to_json
        else
          block.call(key, value)
        end
      end

      def sanitize(key, value)
        case value
        when Integer
          if VALUES_RE.match(clean_invalid_utf8_bytes(value.to_s)) || FIELDS_RE.match(key)
            INT_MASK
          else
            value
          end
        when String
          if value.empty?
            value
          elsif VALUES_RE.match(clean_invalid_utf8_bytes(value)) || FIELDS_RE.match(key)
            STRING_MASK
          else
            clean_invalid_utf8_bytes(value)
          end
        else
          value
        end
      end

      def process(data)
        apply(data) do |key, value|
          sanitize(key, value)
        end
      end

      private

      def clean_invalid_utf8_bytes(text)
        if RUBY_VERSION <= '1.8.7'
          text
        else
          utf16 = text.encode(
            'UTF-16',
            :invalid => :replace,
            :undef => :replace,
            :replace => ''
          )
          utf16.encode('UTF-8')
        end
      end

      def parse_json_or_nil(json)
        begin
          JSON.parse(json)
        rescue JSON::ParserError
          nil
        end
      end
    end
  end
end
