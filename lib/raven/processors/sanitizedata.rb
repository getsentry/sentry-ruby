require 'raven/processor'

module Raven
  module Processor
    class SanitizeData < Processor

      MASK = '********'
      FIELDS_RE = /(password|passwd|secret)/i
      VALUES_RE = /^\d{16}$/

      def apply(value, callback, key=nil)
        if value.is_a?(Hash)
          value.each do |k, v|
            value[k] = apply(v, callback, k)
          end
        elsif value.is_a?(Array)
          value.map do |value|
            apply(value, callback, key)
          end
        else
          callback.call(key, value)
        end
      end

      def sanitize(key, value)
        if value.empty?
          value
        elsif VALUES_RE.match(value) or FIELDS_RE.match(key)
          MASK
        else
          value
        end
      end

      def process(data)
        apply(data, method(:sanitize))
      end
    end
  end
end