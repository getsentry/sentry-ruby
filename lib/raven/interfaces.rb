require 'hashie'

module Raven

  INTERFACES = {}

  class Interface < Hashie::Dash
    def initialize(attributes = {})
      @check_required = false
      super(attributes)
      yield self if block_given?
      @check_required = true
      assert_required_properties_set!
    end

    def assert_property_required!(property, value)
    end

    def assert_required_properties_set!
    end

    def self.name(value=nil)
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
