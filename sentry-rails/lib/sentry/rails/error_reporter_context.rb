# frozen_string_literal: true

module Sentry
  module Rails
    module ErrorReporterContext
      PRIMITIVE_CLASSES = [String, Numeric, Symbol, NilClass, TrueClass, FalseClass].freeze

      def self.contexts
        return {} unless defined?(::ActiveSupport::ExecutionContext)

        execution_context = ::ActiveSupport::ExecutionContext.to_h
        return {} if execution_context.empty?

        { "rails.error" => execution_context.transform_values { |value| sanitize(value) } }
      end

      def self.sanitize(value)
        PRIMITIVE_CLASSES.any? { |klass| value.is_a?(klass) } ? value : value.class.name
      end
    end
  end
end
