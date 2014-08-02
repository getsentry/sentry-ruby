require 'set'

module Raven
  module BetterAttrAccessor

    def attributes
      Hash[
        self.class.attributes.map do |attr|
          [attr, send(attr)]
        end
      ]
    end

    def assert_required_attributes_set!
      self.class.required_attributes.each do |attr|
        raise "#{attr} must be set" if send(attr).nil?
      end
    end

    def self.included(base)
      base.extend ClassMethods
    end

    module ClassMethods
      def attributes
        @attributes ||= Set.new

        if superclass.include? BetterAttrAccessor
          @attributes + superclass.attributes
        else
          @attributes
        end
      end

      def required_attributes
        @required_attributes ||= Set.new
      end

      def attr_accessor(attr, options = {})
        @attributes ||= Set.new
        @attributes << attr.to_sym

        required_attributes << attr.to_sym if options[:required]

        define_method attr do
          instance_variable_get("@#{attr}") || options[:default]
        end
        attr_writer attr
      end
    end
  end
end
