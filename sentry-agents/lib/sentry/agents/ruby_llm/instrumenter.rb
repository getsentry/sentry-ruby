# frozen_string_literal: true

require "json"
require "sentry/agents/ruby_llm/serializer"

module Sentry
  module Agents
    module RubyLLM
      class Instrumenter
        CHAT_EVENT = "chat.ruby_llm"
        USAGE_EVENT = "usage.ruby_llm"
        OPERATION = "gen_ai.chat"
        ORIGIN = "auto.ai.ruby_llm"

        def self.install(config)
          config.instrumenter = new
        end

        def instrument(name, payload)
          case name.to_s
          when CHAT_EVENT
            with_chat_span(payload) { yield } if block_given?
          when USAGE_EVENT
            update_usage(payload)
            yield if block_given?
          else
            yield if block_given?
          end
        end

        private

        def with_chat_span(payload)
          return yield unless Sentry.initialized?

          if Sentry.get_current_scope.get_span
            with_child_span(payload) { yield }
          else
            with_root_transaction(payload) { yield }
          end
        end

        def with_child_span(payload)
          Sentry.with_child_span(
            op: OPERATION,
            description: span_description(payload),
            origin: ORIGIN
          ) do |span|
            execute_span(span, payload) { yield }
          end
        end

        def with_root_transaction(payload)
          transaction = Sentry.start_transaction(
            name: span_description(payload),
            op: OPERATION,
            origin: ORIGIN
          )

          begin
            Sentry.with_scope do |scope|
              scope.set_span(transaction)
              execute_span(transaction, payload) { yield }
            end
          ensure
            transaction.finish
          end
        end

        def execute_span(span, payload)
          set_request_data(span, payload)
          yield
        ensure
          set_response_data(span, payload)
        end

        def set_request_data(span, payload)
          span.set_data(Sentry::Span::DataConventions::GEN_AI_OPERATION_NAME, "chat")

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
        rescue => e
          Sentry.sdk_logger.debug(Sentry::LOGGER_PROGNAME) { "Failed to set RubyLLM request data: #{e}" }
        end

        def set_response_data(span, payload)
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
        rescue => e
          Sentry.sdk_logger.debug(Sentry::LOGGER_PROGNAME) { "Failed to set RubyLLM response data: #{e}" }
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
