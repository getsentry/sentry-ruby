module Raven
  class Processor::SanitizeData < Processor
    STRING_MASK = '********'
    INT_MASK = 0
    FIELDS_RE = /(authorization|password|passwd|secret|ssn|social(.*)?sec)/i
    VALUES_RE = /^\d{16}$/

    def process(value)
      value.inject(value) do |value,(k,v)|
        v = k if v.nil?
        if v.is_a?(Hash) || v.is_a?(Array)
          process(v)
        elsif v.is_a?(String) && (json = parse_json_or_nil(v))
          #if this string is actually a json obj, convert and sanitize
          value = modify_in_place(value, [k,v], process(json).to_json)
        elsif v.is_a?(Integer) && (VALUES_RE.match(v.to_s) || FIELDS_RE.match(k.to_s))
          value = modify_in_place(value, [k,v], INT_MASK)
        elsif VALUES_RE.match(v.to_s) || FIELDS_RE.match(k.to_s)
          value = modify_in_place(value, [k,v], STRING_MASK)
        else
          value
        end
      end
      value
    end

    private

    def modify_in_place(original_parent, original_child, new_child)
      if original_parent.is_a?(Array)
        index = original_parent.index(original_child[0])
        original_parent[index] = new_child
      elsif original_parent.is_a?(Hash)
        original_parent[original_child[0]] = new_child
      end
      original_parent
    end
  end
end

