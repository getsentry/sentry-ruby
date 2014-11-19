module Raven
  class Processor::SanitizeData < Processor
    STRING_MASK = '********'
    INT_MASK = 0
    DEFAULT_FIELDS = %w(authorization password passwd secret ssn social(.*)?sec)
    VALUES_RE = /^\d{16}$/

    def process(value)
      fields_re = /(#{(DEFAULT_FIELDS + @sanitize_fields).join("|")})/i

      value.inject(value) do |memo,(k,v)|
        v = k if v.nil?
        memo = if v.is_a?(Hash) || v.is_a?(Array)
          modify_in_place(memo, k, process(v))
        elsif v.is_a?(String) && (json = parse_json_or_nil(v))
          #if this string is actually a json obj, convert and sanitize
          modify_in_place(memo, k, process(json).to_json)
        elsif v.is_a?(Integer) && (VALUES_RE.match(v.to_s) || fields_re.match(k.to_s))
          modify_in_place(memo, k, INT_MASK)
        elsif VALUES_RE.match(v.to_s) || fields_re.match(k.to_s)
          modify_in_place(memo, k, STRING_MASK)
        else
          memo
        end
      end
    end

    private

    def modify_in_place(original_parent, original_child, new_value)
      if original_parent.is_a?(Array)
        index = original_parent.index(original_child)
        original_parent[index] = new_value
      elsif original_parent.is_a?(Hash)
        original_parent[original_child] = new_value
      end
      original_parent
    end
  end
end

