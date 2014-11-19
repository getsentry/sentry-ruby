module Raven
  class Processor::SanitizeData < Processor
    STRING_MASK = '********'
    INT_MASK = 0
    DEFAULT_FIELDS = %w(authorization password passwd secret ssn social(.*)?sec)
    VALUES_RE = /^\d{16}$/

    def process(value)
      value.inject(value) { |memo,(k,v)|  memo[k] = sanitize(k,v); memo }
    end

    def sanitize(k,v)
      if v.is_a?(Hash)
        process(v)
      elsif v.is_a?(Array)
        v.map{|a| sanitize(nil, a)}
      elsif v.is_a?(String) && (json = parse_json_or_nil(v))
        #if this string is actually a json obj, convert and sanitize
        json.is_a?(Hash) ? process(json).to_json : v
      elsif v.is_a?(Integer) && (VALUES_RE.match(v.to_s) || fields_re.match(k.to_s))
        INT_MASK
      elsif v.is_a?(String)  && (VALUES_RE.match(v.to_s) || fields_re.match(k.to_s))
        STRING_MASK
      else
        v
      end
    end

    private

    def fields_re
      @fields_re ||= /(#{(DEFAULT_FIELDS + @sanitize_fields).join("|")})/i
    end
  end
end

