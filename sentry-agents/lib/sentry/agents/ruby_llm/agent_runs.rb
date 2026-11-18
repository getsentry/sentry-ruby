# frozen_string_literal: true

require "ruby_llm/agent"
require "ruby_llm/chat"

module Sentry
  module Agents
    module RubyLLM
      module AgentRuns
        AGENT_NAME_IVAR = :@sentry_agents_agent_name
        DEPTH_IVAR = :@sentry_agents_agent_run_depth
        OPERATION = "gen_ai.invoke_agent"
        ORIGIN = "auto.ai.ruby_llm"

        module AgentIdentityPatch
          def apply_configuration(chat, input_values:, persist_instructions:, **options)
            result = super(chat, input_values: input_values, persist_instructions: persist_instructions, **options)
            chat.instance_variable_set(AGENT_NAME_IVAR, name.to_s)
            result
          end
        end

        module ChatPatch
          def complete(*args, **kwargs, &block)
            AgentRuns.with(self) { super(*args, **kwargs, &block) }
          end

          def generate(*args, **kwargs, &block)
            AgentRuns.with(self) { super(*args, **kwargs, &block) }
          end

          def run_tools(*args, **kwargs, &block)
            AgentRuns.with(self) { super(*args, **kwargs, &block) }
          end

          def step(*args, **kwargs, &block)
            AgentRuns.with(self) { super(*args, **kwargs, &block) }
          end
        end

        class << self
          def install
            install_agent_identity
            install_chat_patch
          end

          def with(chat)
            agent_name = chat.instance_variable_get(AGENT_NAME_IVAR)
            return yield if agent_name.nil? || agent_name.empty?

            depth = chat.instance_variable_get(DEPTH_IVAR).to_i
            return yield if depth.positive?

            chat.instance_variable_set(DEPTH_IVAR, depth + 1)
            with_span(chat, agent_name) { yield }
          ensure
            if depth&.positive?
              depth.zero? ? chat.remove_instance_variable(DEPTH_IVAR) : chat.instance_variable_set(DEPTH_IVAR, depth)
            end
          end

          private

          def install_agent_identity
            target = ::RubyLLM::Agent.singleton_class
            target.prepend(AgentIdentityPatch) unless target.ancestors.include?(AgentIdentityPatch)
          end

          def install_chat_patch
            target = ::RubyLLM::Chat
            target.prepend(ChatPatch) unless target.ancestors.include?(ChatPatch)
          end

          def with_span(chat, agent_name)
            return yield unless Sentry.initialized?

            scope = Sentry.get_current_scope
            current_span = scope&.get_span
            if current_span
              with_child_span(scope, current_span, chat, agent_name) { yield }
            else
              with_root_transaction(chat, agent_name) { yield }
            end
          end

          def with_child_span(scope, current_span, chat, agent_name)
            span = nil
            begin
              span = current_span.start_child(op: OPERATION, description: description(agent_name), origin: ORIGIN)
              scope.set_span(span)
            rescue StandardError => error
              safe_finish(span)
              report(error)
              return yield
            end

            execute_span(span, scope: scope, previous_span: current_span, chat: chat, agent_name: agent_name) { yield }
          end

          def with_root_transaction(chat, agent_name)
            transaction = begin
              Sentry.start_transaction(name: description(agent_name), op: OPERATION, origin: ORIGIN)
            rescue StandardError => error
              report(error)
              nil
            end
            return yield unless transaction

            application_called = false
            begin
              Sentry.with_scope do |scope|
                scope.set_span(transaction)
                execute_span(transaction, chat: chat, agent_name: agent_name) do
                  application_called = true
                  yield
                end
              end
            rescue StandardError => error
              raise if application_called

              safe_finish(transaction)
              report(error)
              yield
            end
          end

          def execute_span(span, chat:, agent_name:, scope: nil, previous_span: nil)
            result = nil
            begin
              set_data(span, chat, agent_name)
              result = yield
            rescue StandardError => error
              set_error(span, error)
              raise
            ensure
              safe_restore_scope(scope, previous_span) if scope && previous_span
              safe_finish(span)
            end
            result
          end

          def set_data(span, chat, agent_name)
            span.set_data("gen_ai.operation.name", "invoke_agent")
            span.set_data("gen_ai.agent.name", agent_name)
            workflow = ::RubyLLM::Support::Instrumentation.current_workflow
            pipeline = workflow && workflow[:workflow_name]
            span.set_data("gen_ai.pipeline.name", pipeline) if pipeline
          rescue StandardError => error
            report(error)
          end

          def set_error(span, error)
            safe_set_data(span, "error.type", error.class.name)
            safe_set_status(span, "internal_error")
          end

          def safe_set_data(span, key, value)
            span.set_data(key, value)
          rescue StandardError => error
            report(error)
          end

          def safe_set_status(span, status)
            span.set_status(status)
          rescue StandardError => error
            report(error)
          end

          def safe_restore_scope(scope, span)
            scope.set_span(span)
          rescue StandardError => error
            report(error)
          end

          def safe_finish(span)
            span&.finish
          rescue StandardError => error
            report(error)
          end

          def report(error)
            Sentry.configuration.sdk_logger.debug("sentry-agents instrumentation failed: #{error.class}: #{error.message}")
          rescue StandardError
            nil
          end

          def description(agent_name)
            "invoke_agent #{agent_name}"
          end
        end
      end
    end
  end
end
