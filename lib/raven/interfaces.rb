require 'raven/better_attr_accessor'

module Raven

  INTERFACES = {}

  class Interface # TODO: indifferent access?
    include BetterAttrAccessor
    alias_method :to_hash, :attributes

    def initialize(attributes = nil)
      attributes.each do |attr, value|
        send "#{attr}=", value
      end if attributes

      yield self if block_given?

      assert_required_attributes_set!
    end

    def self.name(value = nil)
      @interface_name ||= value
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
