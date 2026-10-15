# frozen_string_literal: true

module Sentry
  module JobExtensions
    class Composite < Extension
      def initialize(extension, default_extension:, registry:)
        super(name: extension.name)
        @extension = extension
        @default_extension = default_extension
        @registry = registry
      end

      Hooks::CONTRACTS.each_key do |hook|
        define_method(hook) do |**arguments|
          default = @registry.call(@default_extension, hook, **arguments)
          arguments = arguments.merge(payload: default) if hook == :inject_trace_headers
          override = @registry.call(@extension, hook, **arguments)
          @default_extension.merge_hook(hook, default: default, override: override)
        end
      end
    end
  end
end
