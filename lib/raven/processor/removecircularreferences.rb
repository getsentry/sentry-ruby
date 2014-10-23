module Raven
  class Processor::RemoveCircularReferences < Processor

    def process(v, visited = [])
      return "(...)" if visited.include?(v.__id__)
      visited += [v.__id__]
      if v.is_a?(Hash)
        v.reduce({}) { |memo, (k, v_)| memo[k] = process(v_, visited); memo }
      elsif v.is_a?(Array)
        v.map { |v_| process(v_, visited) }
      elsif v.is_a?(String) && json_hash = parse_json_or_nil(v)
        v.reduce({}) { |memo, (k, v_)| memo[k] = process(v_, visited); memo }.to_json
      end
    end

  end
end
