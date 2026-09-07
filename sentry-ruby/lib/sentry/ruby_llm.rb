# frozen_string_literal: true

module Sentry
  module RubyLLM
    OP_NAME = "gen_ai.chat"
    EXECUTE_TOOL_OP_NAME = "gen_ai.execute_tool"
    SPAN_ORIGIN = "auto.gen_ai.ruby_llm"
    LOGGER_NAME = :ruby_llm_logger

    module Patch
      def ask(message = nil, with: nil, &block)
        return super unless Sentry.initialized?

        Sentry.with_child_span(op: OP_NAME, start_timestamp: Sentry.utc_now.to_f, origin: SPAN_ORIGIN) do |span|
          result = super
          model_id = @model&.id

          if span
            span.set_description("chat #{model_id}")
            span.set_data("gen_ai.operation.name", "chat")
            span.set_data("gen_ai.request.model", model_id)
            span.set_data("gen_ai.system", @model&.provider)

            if (response = @messages&.last)
              span.set_data("gen_ai.response.model", response.model_id) if response.respond_to?(:model_id)

              if response.respond_to?(:input_tokens) && response.input_tokens
                span.set_data("gen_ai.usage.input_tokens", response.input_tokens)
              end

              if response.respond_to?(:output_tokens) && response.output_tokens
                span.set_data("gen_ai.usage.output_tokens", response.output_tokens)
              end
            end

            if instance_variable_defined?(:@temperature) && @temperature
              span.set_data("gen_ai.request.temperature", @temperature)
            end
          end

          record_breadcrumb("chat", model_id, @model&.provider)

          result
        end
      end

      def execute_tool(tool_call)
        return super unless Sentry.initialized?

        Sentry.with_child_span(op: EXECUTE_TOOL_OP_NAME, start_timestamp: Sentry.utc_now.to_f, origin: SPAN_ORIGIN) do |span|
          result = super

          if span
            span.set_description("execute_tool #{tool_call.name}")
            span.set_data("gen_ai.operation.name", "execute_tool")
            span.set_data("gen_ai.tool.name", tool_call.name)
            span.set_data("gen_ai.tool.call.id", tool_call.id)
            span.set_data("gen_ai.tool.type", "function")

            if Sentry.configuration.send_default_pii
              span.set_data("gen_ai.tool.call.arguments", tool_call.arguments.to_json) if tool_call.arguments
              span.set_data("gen_ai.tool.call.result", result.to_s[0..499]) if result
            end
          end

          result
        end
      end

      private

      def record_breadcrumb(operation, name, provider = nil)
        return unless Sentry.initialized?
        return unless Sentry.configuration.breadcrumbs_logger.include?(LOGGER_NAME)

        Sentry.add_breadcrumb(
          Sentry::Breadcrumb.new(
            level: :info,
            category: OP_NAME,
            type: :info,
            data: {
              operation: operation,
              name: name,
              provider: provider
            }.compact
          )
        )
      end
    end
  end
end

Sentry.register_patch(:ruby_llm) do
  if defined?(::RubyLLM::Chat)
    ::RubyLLM::Chat.prepend(Sentry::RubyLLM::Patch)
  end
end
