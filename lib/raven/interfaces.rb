require 'hashie'

module Raven

  INTERFACES = {}

  class Interface < Hashie::Dash
    if defined?(Hashie::Extensions::Dash::IndifferentAccess)
      include Hashie::Extensions::Dash::IndifferentAccess
    end

    def initialize(attributes = {}, &block)
      @check_required = false
      super(attributes)
      block.call(self) if block
      @check_required = true

      if self.private_methods.include?(:assert_required_attributes_set!)
        assert_required_attributes_set!
      else
        assert_required_properties_set!
      end
    end

    def assert_required_attributes_set!
      super if @check_required
    end

    def assert_required_properties_set!
      super if @check_required
    end

    def self.name(value = nil)
      @interface_name = value if value
      @interface_name
    end
  end

  def self.register_interface(mapping)
    mapping.each_pair do |key, klass|
      INTERFACES[key.to_s] = klass
      INTERFACES[klass.name] = klass
    end
  end

  def self.find_interface(name)
    INTERFACES[name.to_s]
  end
end
