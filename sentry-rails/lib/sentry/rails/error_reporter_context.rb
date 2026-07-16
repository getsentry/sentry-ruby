# frozen_string_literal: true

require "sentry/rails/serializer"

module Sentry
  module Rails
    module ErrorReporterContext
      SUPPORTS_EXECUTION_CONTEXT = Gem::Version.new(::Rails.version) >= Gem::Version.new("7.0.0")

      class << self
        if SUPPORTS_EXECUTION_CONTEXT
          def contexts
            execution_context = ::ActiveSupport::ExecutionContext.to_h
            return {} if execution_context.empty?

            { "rails.error" => Sentry::Rails::Serializer.serialize(execution_context) }
          end
        else
          def contexts
            {}
          end
        end
      end
    end
  end
end
