require 'raven/processor'

module Raven
  module Processor
    class SanitizeData < Processor

      MASK = '********'
      FIELDS_RE = /(authorization|password|passwd|secret)/i
      VALUES_RE = /^\d{16}$/

      def apply(value, key=nil, &block)
        if value.is_a?(Hash)
          value.each.inject({}) do |memo, (k, v)|
            memo[k] = apply(v, k, &block)
            memo
          end
        elsif value.is_a?(Array)
          value.map do |value|
            apply(value, key, &block)
          end
        else
          block.call(key, value)
        end
      end

      def sanitize(key, value)
        if !value || value.empty?
          value
        elsif VALUES_RE.match(value) or FIELDS_RE.match(key)
          MASK
        else
          value
        end
      end

      def process(data)
        apply(data) do |key, value|
          sanitize(key, value)
        end
      end
    end
  end
end