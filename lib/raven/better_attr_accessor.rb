require 'set'

module Raven
  module BetterAttrAccessor

    def attributes
      Hash[
        self.class.attributes.map do |attr|
          [attr.to_sym, send(attr)]
        end
      ]
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

      def attr_accessor(attr, options = {})
        @attributes ||= Set.new
        @attributes << attr

        define_method attr do
          if instance_variable_defined? "@#{attr}"
            instance_variable_get "@#{attr}"
          elsif options.key? :default
            instance_variable_set "@#{attr}", options[:default].dup
          end
        end
        attr_writer attr
      end
    end
  end
end
