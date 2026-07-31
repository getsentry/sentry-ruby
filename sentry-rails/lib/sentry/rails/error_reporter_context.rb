# frozen_string_literal: true

require "sentry/rails/serializer"

module Sentry
  module Rails
    module ErrorReporterContext
      SUPPORTS_EXECUTION_CONTEXT = Gem::Version.new(::Rails.version) >= Gem::Version.new("7.0.0")

      if SUPPORTS_EXECUTION_CONTEXT
        def execution_context
          return {} unless Sentry.configuration.send_default_pii

          context = ::ActiveSupport::ExecutionContext.to_h
          return {} if context.empty?

          { "rails.error" => Sentry::Rails::Serializer.serialize(context) }
        end
      else
        def execution_context
          {}
        end
      end
    end
  end
end
