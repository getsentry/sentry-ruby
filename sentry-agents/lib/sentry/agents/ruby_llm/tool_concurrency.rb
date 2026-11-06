# frozen_string_literal: true

require "ruby_llm/chat/tool_concurrency"

module Sentry
  module Agents
    module RubyLLM
      class HubContext
        def self.capture
          return unless Sentry.initialized?

          hub = Sentry.get_current_hub
          new(hub, hub.current_scope&.get_span)
        rescue StandardError => error
          report(error)
          nil
        end

        def initialize(hub, span)
          @hub = hub
          @span = span
        end

        def with_hub
          previous_hub = Sentry.send(:get_current_hub_internal)
          begin
            hub = @hub.clone
            hub.current_scope.set_span(@span) if @span
            Sentry.send(:set_current_hub_internal, hub)
          rescue StandardError => error
            self.class.report(error)
            return yield
          end

          begin
            yield
          ensure
            Sentry.send(:set_current_hub_internal, previous_hub)
          end
        end

        class << self
          def report(error)
            Sentry.configuration.sdk_logger.debug("sentry-agents instrumentation failed: #{error.class}: #{error.message}")
          rescue StandardError
            nil
          end
        end
      end

      module ToolConcurrency
        module Patch
          def run(mode, tool_calls, on_result: nil, &execute)
            context = HubContext.capture
            return super unless context

            super(mode, tool_calls, on_result: on_result) do |tool_call|
              context.with_hub { execute.call(tool_call) }
            end
          end
        end

        module_function

        def install
          target = ::RubyLLM::Chat::ToolConcurrency
          return if target.singleton_class.ancestors.include?(Patch)

          target.singleton_class.prepend(Patch)
        end
      end
    end
  end
end
