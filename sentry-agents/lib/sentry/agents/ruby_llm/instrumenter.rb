# frozen_string_literal: true

require "json"
require "sentry/agents/ruby_llm/serializer"

module Sentry
  module Agents
    module RubyLLM
      class Instrumenter
        CHAT_EVENT = "chat.ruby_llm"
        TOOL_EVENT = "tool_call.ruby_llm"
        WORKFLOW_EVENT = "workflow.ruby_llm"
        WORKFLOW_STEP_EVENT = "workflow_step.ruby_llm"
        USAGE_EVENT = "usage.ruby_llm"
        OPERATION = "gen_ai.chat"
        TOOL_OPERATION = "gen_ai.execute_tool"
        WORKFLOW_OPERATION = "ai.pipeline"
        WORKFLOW_STEP_OPERATION = "ai.run"
        ORIGIN = "auto.ai.ruby_llm"

        def self.install(config)
          config.instrumenter = new
        end

        def instrument(name, payload)
          case name.to_s
          when CHAT_EVENT
            with_chat_span(payload) { yield } if block_given?
          when TOOL_EVENT
            with_tool_span(payload) { yield } if block_given?
          when WORKFLOW_EVENT
            with_operation_span(payload, WORKFLOW_OPERATION, workflow_description(payload)) { yield } if block_given?
          when WORKFLOW_STEP_EVENT
            with_operation_span(payload, WORKFLOW_STEP_OPERATION, workflow_step_description(payload)) { yield } if block_given?
          when USAGE_EVENT
            update_usage(payload)
            yield if block_given?
          else
            yield if block_given?
          end
        end

        private

        def with_chat_span(payload)
          with_operation_span(payload, OPERATION, span_description(payload)) { yield }
        end

        def with_tool_span(payload)
          with_operation_span(payload, TOOL_OPERATION, tool_description(payload)) { yield }
        end

        def with_operation_span(payload, operation, description)
          return yield unless Sentry.initialized?

          if Sentry.get_current_scope.get_span
            with_child_span(payload, operation, description) { yield }
          else
            with_root_transaction(payload, operation, description) { yield }
          end
        end

        def with_child_span(payload, operation, description)
          Sentry.with_child_span(op: operation, description: description, origin: ORIGIN) do |span|
            execute_span(span, payload, operation) { yield }
          end
        end

        def with_root_transaction(payload, operation, description)
          transaction = Sentry.start_transaction(name: description, op: operation, origin: ORIGIN)

          begin
            Sentry.with_scope do |scope|
              scope.set_span(transaction)
              execute_span(transaction, payload, operation) { yield }
            end
          ensure
            transaction.finish
          end
        end

        def execute_span(span, payload, operation)
          set_request_data(span, payload, operation)
          yield
        ensure
          set_response_data(span, payload, operation)
        end

        def set_request_data(span, payload, operation)
          case operation
          when OPERATION
            set_chat_request_data(span, payload)
          when TOOL_OPERATION
            set_tool_request_data(span, payload)
          when WORKFLOW_OPERATION, WORKFLOW_STEP_OPERATION
            set_pipeline_data(span, payload)
          end
        rescue => e
          Sentry.sdk_logger.debug(Sentry::LOGGER_PROGNAME) { "Failed to set RubyLLM request data: #{e}" }
        end

        def set_chat_request_data(span, payload)
          span.set_data(Sentry::Span::DataConventions::GEN_AI_OPERATION_NAME, "chat")
          set_pipeline_data(span, payload)
          set_agent_data(span, payload)

          if provider = provider_name(payload[:provider])
            span.set_data(Sentry::Span::DataConventions::GEN_AI_PROVIDER_NAME, provider)
          end

          if model = payload[:model]&.to_s
            span.set_data(Sentry::Span::DataConventions::GEN_AI_REQUEST_MODEL, model)
          end

          if temperature = payload[:temperature]
            span.set_data(Sentry::Span::DataConventions::GEN_AI_REQUEST_TEMPERATURE, temperature)
          end

          if max_tokens = payload[:max_output_tokens]
            span.set_data(Sentry::Span::DataConventions::GEN_AI_REQUEST_MAX_TOKENS, max_tokens)
          end

          if stream = !!payload[:streaming]
            span.set_data(Sentry::Span::DataConventions::GEN_AI_REQUEST_STREAM, stream)
          end

          if reasoning_level = payload[:thinking]&.effort&.to_s
            span.set_data(Sentry::Span::DataConventions::GEN_AI_REQUEST_REASONING_LEVEL, reasoning_level)
          end

          return unless collect_inputs?

          system, non_system = Serializer.messages(payload[:input_messages])
          if non_system.any?
            span.set_data(Sentry::Span::DataConventions::GEN_AI_INPUT_MESSAGES, JSON.generate(non_system))
          end
          if system.any?
            span.set_data(Sentry::Span::DataConventions::GEN_AI_SYSTEM_INSTRUCTIONS, JSON.generate(system))
          end

          definitions = Serializer.tool_definitions(payload)
          if definitions.any?
            span.set_data(Sentry::Span::DataConventions::GEN_AI_TOOL_DEFINITIONS, JSON.generate(definitions))
          end
        end

        def set_tool_request_data(span, payload)
          span.set_data(Sentry::Span::DataConventions::GEN_AI_OPERATION_NAME, "execute_tool")
          set_pipeline_data(span, payload)
          set_agent_data(span, payload)

          if tool_name = payload[:tool_name] || payload[:tool]&.name
            span.set_data(Sentry::Span::DataConventions::GEN_AI_TOOL_NAME, tool_name.to_s)
          end

          return unless collect_inputs?

          if arguments = payload[:tool_arguments]
            span.set_data(Sentry::Span::DataConventions::GEN_AI_TOOL_CALL_ARGUMENTS, JSON.generate(arguments))
          end
        end

        def set_pipeline_data(span, payload)
          if pipeline_name = payload[:workflow_name]
            span.set_data(Sentry::Span::DataConventions::GEN_AI_PIPELINE_NAME, pipeline_name.to_s)
          end
        end

        def set_agent_data(span, payload)
          chat = payload[:chat]
          if agent_name = chat&.instance_variable_get(:@sentry_agents_agent_name)
            span.set_data(Sentry::Span::DataConventions::GEN_AI_AGENT_NAME, agent_name.to_s)
          end
        end

        def set_response_data(span, payload, operation)
          case operation
          when OPERATION
            set_chat_response_data(span, payload)
          when TOOL_OPERATION
            set_tool_response_data(span, payload)
          end
        rescue => e
          Sentry.sdk_logger.debug(Sentry::LOGGER_PROGNAME) { "Failed to set RubyLLM response data: #{e}" }
        end

        def set_chat_response_data(span, payload)
          response = payload[:response]
          response_model = payload[:response_model] || response&.model
          finish_reason = response&.finish_reason

          if response_model = response_model&.to_s
            span.set_data(Sentry::Span::DataConventions::GEN_AI_RESPONSE_MODEL, response_model)
          end

          if finish_reasons = (Array(finish_reason).map(&:to_s) if finish_reason)
            span.set_data(Sentry::Span::DataConventions::GEN_AI_RESPONSE_FINISH_REASONS, finish_reasons)
          end

          return unless collect_outputs? && response

          messages = [Serializer.normalize_message(response)]
          if messages.any?
            span.set_data(Sentry::Span::DataConventions::GEN_AI_OUTPUT_MESSAGES, JSON.generate(messages))
          end
        end

        def set_tool_response_data(span, payload)
          return unless collect_outputs?
          return unless payload.key?(:result) || payload.key?(:result_content)

          result = payload.key?(:result) ? payload[:result] : payload[:result_content]
          span.set_data(Sentry::Span::DataConventions::GEN_AI_TOOL_CALL_RESULT, JSON.generate(result))
        end

        def update_usage(payload)
          return unless Sentry.initialized?

          span = Sentry.get_current_scope&.get_span
          return unless span&.op == OPERATION

          tokens = payload[:tokens]
          return unless tokens

          input_tokens = [tokens.input, tokens.cache_read, tokens.cache_write].compact
          add_usage(span, Sentry::Span::DataConventions::GEN_AI_USAGE_INPUT_TOKENS, input_tokens.sum) unless input_tokens.empty?
          add_usage(span, Sentry::Span::DataConventions::GEN_AI_USAGE_OUTPUT_TOKENS, tokens.output)
          add_usage(span, Sentry::Span::DataConventions::GEN_AI_USAGE_CACHE_READ_INPUT_TOKENS, tokens.cache_read)
          add_usage(span, Sentry::Span::DataConventions::GEN_AI_USAGE_CACHE_CREATION_INPUT_TOKENS, tokens.cache_write)
          add_usage(span, Sentry::Span::DataConventions::GEN_AI_USAGE_REASONING_OUTPUT_TOKENS, tokens.thinking)
        rescue => e
          Sentry.sdk_logger.debug(Sentry::LOGGER_PROGNAME) { "Failed to update RubyLLM usage: #{e}" }
        end

        def add_usage(span, key, value)
          return if value.nil?

          previous = span.data[key]
          span.set_data(key, previous.nil? ? value : previous + value)
        end

        def span_description(payload)
          model = payload[:model]
          model ? "chat #{model}" : "chat"
        end

        def provider_name(provider)
          ::RubyLLM::OpenTelemetry::Attributes.provider_name(provider)
        end

        def tool_description(payload)
          tool = payload[:tool_name] || payload[:tool]&.name
          tool ? "execute_tool #{tool}" : "execute_tool"
        end

        def workflow_description(payload)
          payload[:workflow_name] || "workflow"
        end

        def workflow_step_description(payload)
          payload[:workflow_step_name] || "workflow step"
        end

        def collect_inputs?
          Sentry.configuration.data_collection.gen_ai.inputs
        end

        def collect_outputs?
          Sentry.configuration.data_collection.gen_ai.outputs
        end
      end
    end
  end
end
