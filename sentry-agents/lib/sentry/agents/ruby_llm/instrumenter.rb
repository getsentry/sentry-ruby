# frozen_string_literal: true

require "json"

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

      attr_reader :delegate

      def self.install(config)
        return config.instrumenter if config.instrumenter.is_a?(self)

        config.instrumenter = new(config.instrumenter)
      end

      def initialize(delegate)
        @delegate = delegate
      end

      def instrument(name, payload = {}, &block)
        event_name = name.to_s
        instrumented_events = [CHAT_EVENT, TOOL_EVENT, WORKFLOW_EVENT, WORKFLOW_STEP_EVENT, USAGE_EVENT]
        return delegate_instrument(name, payload, &block) unless instrumented_events.include?(event_name)

        if event_name == USAGE_EVENT
          update_usage(payload)
          return delegate_instrument(name, payload, &block)
        end

        return delegate_instrument(name, payload, &block) unless block

        delegate_instrument(name, payload) do |event|
          event = event || payload
          case event_name
          when CHAT_EVENT
            with_chat_span(event) { yield(event) }
          when TOOL_EVENT
            with_tool_span(event) { yield(event) }
          when WORKFLOW_EVENT
            with_operation_span(event, WORKFLOW_OPERATION, workflow_description(event)) { yield(event) }
          when WORKFLOW_STEP_EVENT
            with_operation_span(event, WORKFLOW_STEP_OPERATION, workflow_step_description(event)) { yield(event) }
          end
        end
      end

      private

      def delegate_instrument(name, payload, &block)
        return delegate.instrument(name, payload, &block) if delegate&.respond_to?(:instrument)
        block.call(payload) if block
      end

      def with_chat_span(payload)
        with_operation_span(payload, OPERATION, span_description(payload)) { yield }
      end

      def with_tool_span(payload)
        with_operation_span(payload, TOOL_OPERATION, tool_description(payload)) { yield }
      end

      def with_operation_span(payload, operation, description)
        return yield unless Sentry.initialized?

        scope = Sentry.get_current_scope
        current_span = scope&.get_span
        return with_child_span(scope, current_span, payload, operation, description) { yield } if current_span

        with_root_transaction(payload, operation, description) { yield }
      end

      def with_child_span(scope, current_span, payload, operation, description)
        span = nil
        begin
          span = current_span.start_child(op: operation, description: description, origin: ORIGIN)
          scope.set_span(span)
        rescue StandardError => error
          safe_finish(span)
          report_instrumentation_error(error)
          return yield
        end

        execute_span(span, payload, operation: operation, scope: scope, previous_span: current_span) { yield }
      end

      def with_root_transaction(payload, operation, description)
        transaction = begin
          Sentry.start_transaction(name: description, op: operation, origin: ORIGIN)
        rescue StandardError => error
          report_instrumentation_error(error)
          nil
        end
        return yield unless transaction

        application_called = false
        begin
          Sentry.with_scope do |scope|
            scope.set_span(transaction)
            execute_span(transaction, payload, operation: operation) do
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

      def execute_span(span, payload, operation:, scope: nil, previous_span: nil)
        result = nil
        begin
          set_request_data(span, payload, operation)
          result = yield
        rescue StandardError => error
          set_error(span, error)
          raise
        ensure
          set_response_data(span, payload, operation)
          safe_restore_scope(scope, previous_span) if scope && previous_span
          safe_finish(span)
        end
        result
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
      rescue StandardError => error
        report_instrumentation_error(error)
      end

      def set_chat_request_data(span, payload)
        safe_set_data(span, "gen_ai.operation.name", "chat")
        set_pipeline_data(span, payload)
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
      end

      def set_tool_request_data(span, payload)
        safe_set_data(span, "gen_ai.operation.name", "execute_tool")
        set_pipeline_data(span, payload)
        set_data_if_present(span, "gen_ai.tool.name", string_value(payload[:tool_name] || Serializer.value(payload[:tool], :name)))
        return unless collect_inputs?

        arguments =
          if payload.key?(:tool_arguments)
            payload[:tool_arguments]
          else
            Serializer.value(payload[:tool_call], :arguments)
          end
        return if arguments.nil?

        set_json_data(span, "gen_ai.tool.call.arguments", arguments)
      end

      def set_pipeline_data(span, payload)
        set_data_if_present(span, "gen_ai.pipeline.name", string_value(payload[:workflow_name]))
      end

      def set_response_data(span, payload, operation)
        case operation
        when OPERATION
          set_chat_response_data(span, payload)
        when TOOL_OPERATION
          set_tool_response_data(span, payload)
        end
      rescue StandardError => error
        report_instrumentation_error(error)
      end

      def set_chat_response_data(span, payload)
        response = payload[:response] || Array(payload[:messages_after]).last
        response_model = payload[:response_model] || Serializer.value(response, :model)
        finish_reason = Serializer.value(response, :finish_reason)

        set_data_if_present(span, "gen_ai.response.model", string_value(response_model))
        set_data_if_present(span, "gen_ai.response.finish_reasons", finish_reason&.to_s)
        return unless collect_outputs? && response

        messages = Serializer.messages([response]).first
        set_json_data(span, "gen_ai.output.messages", messages) unless messages.empty?
      end

      def set_tool_response_data(span, payload)
        return unless collect_outputs?
        return unless payload.key?(:result) || payload.key?(:result_content)

        result = payload.key?(:result) ? payload[:result] : payload[:result_content]
        set_json_data(span, "gen_ai.tool.call.result", result)
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

      def tool_description(payload)
        tool = payload[:tool_name] || Serializer.value(payload[:tool], :name)
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
