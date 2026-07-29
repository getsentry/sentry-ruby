# frozen_string_literal: true

require "sentry/rails/serializer"
require "sentry/rails/parameter_filter"

module Sentry
  module Rails
    module ErrorReporterContext
      SUPPORTS_EXECUTION_CONTEXT = Gem::Version.new(::Rails.version) >= Gem::Version.new("7.0.0")

      # Serialize a context hash and redact anything matching the application's
      # `config.filter_parameters`, so that user data attached via `Rails.error.set_context`
      # gets the same treatment whether it reaches us through
      # `ActiveSupport::ExecutionContext` or through the error reporter.
      #
      # Serialization runs first: the serializer expands Enumerables and Ranges into arrays the
      # filter can descend into, and it preserves hash keys, so filtering its output is strictly
      # more thorough than filtering the raw context.
      #
      # @param context [Hash] the raw context
      # @return [Hash] the serialized context with sensitive values redacted
      def sanitize_context(context)
        Sentry::Rails::ParameterFilter.filter_sensitive_params(Sentry::Rails::Serializer.serialize(context))
      end

      if SUPPORTS_EXECUTION_CONTEXT
        def execution_context
          context = ::ActiveSupport::ExecutionContext.to_h
          return {} if context.empty?

          { "rails.error" => sanitize_context(context) }
        end
      else
        def execution_context
          {}
        end
      end
    end
  end
end
