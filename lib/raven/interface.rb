module Raven
  class Interface
    def initialize(attributes = nil)
      attributes.each do |attr, value|
        public_send "#{attr}=", value
      end if attributes

      yield self if block_given?
    end

    def to_hash
      instance_variables.each_with_object({}) do |name, memo|
        value = instance_variable_get(name)
        memo[name[1..-1].to_sym] = value if value
      end
    end
  end
end
