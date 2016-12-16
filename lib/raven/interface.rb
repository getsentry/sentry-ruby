module Raven
  class Interface
    def initialize(init = {})
      init.each_pair { |key, val| public_send(key.to_s + "=", val) }

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
      Hash[instance_variables.map { |name| [name[1..-1].to_sym, instance_variable_get(name)] }]
    end
  end
end
