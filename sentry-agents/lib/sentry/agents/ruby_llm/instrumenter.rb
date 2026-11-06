# frozen_string_literal: true

require "json"

module Sentry
  module Agents
    module RubyLLM
      class Instrumenter
      CHAT_EVENT = "chat.ruby_llm"
      USAGE_EVENT = "usage.ruby_llm"
      OPERATION = "gen_ai.chat"
      ORIGIN = "auto.ai.ruby_llm"

      attr_reader :delegate

      def self.install(config)
        return config.instrumenter if config.instrumenter.is_a?(self)

        config.instrumenter = new(config.instrumenter)
      end

      def initialize(delegate)
        @delegate = delegate
      end

      def instrument(name, payload = {}, &block)
        return delegate_instrument(name, payload, &block) unless name.to_s == CHAT_EVENT || name.to_s == USAGE_EVENT

        if name.to_s == USAGE_EVENT
          update_usage(payload)
          return delegate_instrument(name, payload, &block)
        end

        return delegate_instrument(name, payload, &block) unless block

        delegate_instrument(name, payload) do |event|
          with_chat_span(event || payload) { yield(event || payload) }
        end
      end

      private

      def delegate_instrument(name, payload, &block)
        return delegate.instrument(name, payload, &block) if delegate&.respond_to?(:instrument)
        block.call(payload) if block
      end

      def with_chat_span(payload)
        return yield unless Sentry.initialized?

        scope = Sentry.get_current_scope
        current_span = scope&.get_span
        return with_child_span(scope, current_span, payload) { yield } if current_span

        with_root_transaction(payload) { yield }
      end

      def with_child_span(scope, current_span, payload)
        span = nil
        begin
          span = current_span.start_child(
            op: OPERATION,
            description: span_description(payload),
            origin: ORIGIN
          )
          scope.set_span(span)
        rescue StandardError => error
          safe_finish(span)
          report_instrumentation_error(error)
          return yield
        end

        execute_span(span, payload, scope: scope, previous_span: current_span) { yield }
      end

      def with_root_transaction(payload)
        transaction = begin
          Sentry.start_transaction(
            name: span_description(payload),
            op: OPERATION,
            origin: ORIGIN
          )
        rescue StandardError => error
          report_instrumentation_error(error)
          nil
        end
        return yield unless transaction

        application_called = false
        begin
          Sentry.with_scope do |scope|
            scope.set_span(transaction)
            execute_span(transaction, payload) do
              application_called = true
              yield
            end
          end
        rescue StandardError => error
          raise if application_called

          safe_finish(transaction)
          report_instrumentation_error(error)
          yield
        end
      end

      def execute_span(span, payload, scope: nil, previous_span: nil)
        result = nil
        begin
          set_request_data(span, payload)
          result = yield
        rescue StandardError => error
          set_error(span, error)
          raise
        ensure
          set_response_data(span, payload)
          safe_restore_scope(scope, previous_span) if scope && previous_span
          safe_finish(span)
        end
        result
      end

      def set_request_data(span, payload)
        safe_set_data(span, "gen_ai.operation.name", "chat")
        set_data_if_present(span, "gen_ai.provider.name", string_value(payload[:provider]))
        set_data_if_present(span, "gen_ai.request.model", string_value(payload[:model]))
        set_data_if_present(span, "gen_ai.request.temperature", payload[:temperature])
        set_data_if_present(span, "gen_ai.request.max_tokens", payload[:max_output_tokens])
        return unless collect_inputs?

        messages, system_instructions = Serializer.messages(payload[:input_messages])
        set_json_data(span, "gen_ai.input.messages", messages) unless messages.empty?
        set_json_data(span, "gen_ai.system_instructions", system_instructions) unless system_instructions.empty?

        definitions = Serializer.tool_definitions(payload)
        set_json_data(span, "gen_ai.tool.definitions", definitions) unless definitions.empty?
      rescue StandardError => error
        report_instrumentation_error(error)
      end

      def set_response_data(span, payload)
        response = payload[:response] || Array(payload[:messages_after]).last
        response_model = payload[:response_model] || Serializer.value(response, :model)
        finish_reason = Serializer.value(response, :finish_reason)

        set_data_if_present(span, "gen_ai.response.model", string_value(response_model))
        set_data_if_present(span, "gen_ai.response.finish_reasons", finish_reason&.to_s)
        return unless collect_outputs? && response

        messages = Serializer.messages([response]).first
        set_json_data(span, "gen_ai.output.messages", messages) unless messages.empty?
      rescue StandardError => error
        report_instrumentation_error(error)
      end

      def update_usage(payload)
        return unless Sentry.initialized?

        span = Sentry.get_current_scope&.get_span
        return unless span&.op == OPERATION

        tokens = payload[:tokens]
        return unless tokens

        input_tokens = sum_tokens(tokens, :input, :cache_read, :cache_write)
        add_usage(span, "gen_ai.usage.input_tokens", input_tokens) unless input_tokens.nil?
        add_usage(span, "gen_ai.usage.output_tokens", token_value(tokens, :output))
        add_usage(span, "gen_ai.usage.cache_read.input_tokens", token_value(tokens, :cache_read))
        add_usage(span, "gen_ai.usage.cache_creation.input_tokens", token_value(tokens, :cache_write))
        add_usage(span, "gen_ai.usage.reasoning.output_tokens", token_value(tokens, :thinking))
      rescue StandardError => error
        report_instrumentation_error(error)
      end

      def sum_tokens(tokens, *names)
        values = names.map { |name| token_value(tokens, name) }
        return if values.all?(&:nil?)

        values.compact.sum
      end

      def token_value(tokens, name)
        if tokens.respond_to?(name)
          tokens.public_send(name)
        elsif tokens.respond_to?(:key?) && tokens.key?(name)
          tokens[name]
        elsif tokens.respond_to?(:key?) && tokens.key?(name.to_s)
          tokens[name.to_s]
        end
      end

      def add_usage(span, key, value)
        return if value.nil?

        previous = span.data[key]
        safe_set_data(span, key, previous.nil? ? value : previous + value)
      end

      def span_description(payload)
        model = payload[:model]
        model ? "chat #{model}" : "chat"
      end

      def collect_inputs?
        Sentry.configuration.data_collection.gen_ai.inputs
      end

      def collect_outputs?
        Sentry.configuration.data_collection.gen_ai.outputs
      end

      def set_error(span, error)
        safe_set_data(span, "error.type", error.class.name)
        safe_set_status(span, "internal_error")
      end

      def set_data_if_present(span, key, value)
        safe_set_data(span, key, value) unless value.nil?
      end

      def string_value(value)
        value&.to_s
      end

      def set_json_data(span, key, value)
        set_data_if_present(span, key, JSON.generate(value))
      rescue StandardError => error
        report_instrumentation_error(error)
      end

      def safe_set_data(span, key, value)
        span.set_data(key, value)
      rescue StandardError => error
        report_instrumentation_error(error)
      end

      def safe_set_status(span, status)
        span.set_status(status)
      rescue StandardError => error
        report_instrumentation_error(error)
      end

      def safe_restore_scope(scope, span)
        scope.set_span(span)
      rescue StandardError => error
        report_instrumentation_error(error)
      end

      def safe_finish(span)
        span&.finish
      rescue StandardError => error
        report_instrumentation_error(error)
      end

      def report_instrumentation_error(error)
        Sentry.configuration.sdk_logger.debug("sentry-agents instrumentation failed: #{error.class}: #{error.message}")
      rescue StandardError
        nil
      end

      module Serializer
        module_function

        def messages(messages)
          messages = Array(messages)
          system = messages.select { |message| value(message, :role).to_s == "system" }
          non_system = messages.reject { |message| value(message, :role).to_s == "system" }

          [non_system.filter_map { |message| normalize_message(message) }, system.flat_map { |message| parts(message) }]
        end

        def tool_definitions(payload)
          chat = payload[:chat]
          tools =
            if chat&.respond_to?(:tools)
              chat.tools.values
            else
              Array(payload[:tools])
            end

          definitions = tools.filter_map do |tool|
            if tool.respond_to?(:name)
              {
                name: tool.name,
                description: tool.description,
                parameters: tool.parameters_schema
              }.compact
            elsif tool.is_a?(Hash)
              tool
            elsif tool
              { name: tool.to_s }
            end
          end

          definitions + Array(payload[:provider_tools]).select { |tool| tool.is_a?(Hash) }
        end

        def normalize_message(message)
          role = normalize_role(value(message, :role))
          { role: role, parts: parts(message) }
        end

        def parts(message)
          role = normalize_role(value(message, :role))
          return [{ type: "tool_call_response", id: value(message, :tool_call_id), response: value(message, :content) }.compact] if role == "tool"

          result = []
          content = value(message, :content)
          result << { type: "text", content: content } unless content.nil?

          tool_calls = value(message, :tool_calls)
          tool_calls = tool_calls.values if tool_calls.is_a?(Hash)
          Array(tool_calls).each do |tool_call|
            result << {
              type: "tool_call",
              id: value(tool_call, :id),
              name: value(tool_call, :name),
              arguments: value(tool_call, :arguments)
            }.compact
          end
          result
        end

        def normalize_role(role)
          case role.to_s
          when "human" then "user"
          when "ai" then "assistant"
          when "function" then "tool"
          else role.to_s
          end
        end

        def value(object, key)
          if object.respond_to?(key)
            object.public_send(key)
          elsif object.respond_to?(:key?) && object.key?(key)
            object[key]
          elsif object.respond_to?(:key?) && object.key?(key.to_s)
            object[key.to_s]
          end
        end
      end
      end
    end
  end
end
