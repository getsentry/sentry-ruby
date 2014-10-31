module Raven
  class Processor::SanitizeData < Processor
    STRING_MASK = '********'
    INT_MASK = 0
    FIELDS_RE = /(authorization|password|passwd|secret|ssn|social(.*)?sec)/i
    VALUES_RE = /^\d{16}$/

    def process(value)
      value.merge(value) do |k, v|
        if v.is_a?(Hash)
          process(v)
        elsif v.is_a?(String) && (json_hash = parse_json_or_nil(v))
          #if this string is actually a json obj, convert and sanitize
          process(json_hash).to_json
        elsif v.is_a?(Integer) && (VALUES_RE.match(v.to_s) || FIELDS_RE.match(k))
          INT_MASK
        elsif VALUES_RE.match(v.to_s) || FIELDS_RE.match(k)
          STRING_MASK
        else
          v
        end
      end
    end
  end
end

