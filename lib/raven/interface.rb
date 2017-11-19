module Raven
  class Interface
    def initialize(attributes = nil)
      attributes.each do |attr, value|
        public_send "#{attr}=", value
      end if attributes

      yield self if block_given?
    end

    def self.inherited(klass)
      name = klass.name.split("::").last.downcase.gsub("interface", "")
      registered[name.to_sym] = klass
      super
    end

    def self.registered
      @@registered ||= {} # rubocop:disable Style/ClassVars
    end

    def to_hash
      instance_variables.each_with_object({}) do |name, memo|
        value = instance_variable_get(name)
        memo[name[1..-1].to_sym] = value if value
      end
    end
  end
end
