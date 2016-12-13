module Raven
  class Processor::RemoveCircularReferences < Processor
    def process(value, visited = [])
      return "(...)" if visited.include?(value.__id__)
      visited << value.__id__ if value.is_a?(Array) || value.is_a?(Hash)

      case value
      when Hash
        !value.frozen? ? value.merge!(value) { |_, v| process v, visited } : value.merge(value) { |_, v| process v, visited }
      when Array
        !value.frozen? ? value.map! { |v| process v, visited } : value.map { |v| process v, visited }
      else
        value
      end
    end
  end
end
