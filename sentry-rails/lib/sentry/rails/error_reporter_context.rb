# frozen_string_literal: true

require "sentry/rails/serializer"
require "sentry/rails/parameter_filter"

module Sentry
  module Rails
    module ErrorReporterContext
      SUPPORTS_EXECUTION_CONTEXT = Gem::Version.new(::Rails.version) >= Gem::Version.new("7.0.0")

      if SUPPORTS_EXECUTION_CONTEXT
        def execution_context
          context = ::ActiveSupport::ExecutionContext.to_h
          return {} if context.empty?

          # Serialize first: the serializer expands Enumerables and Ranges into arrays the
          # filter can descend into, and it preserves hash keys, so filtering its output is
          # strictly more thorough than filtering the raw context.
          { "rails.error" => Sentry::Rails::ParameterFilter.filter_sensitive_params(Sentry::Rails::Serializer.serialize(context)) }
        end
      else
        def execution_context
          {}
        end
      end
    end
  end
end
