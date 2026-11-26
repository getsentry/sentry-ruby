# frozen_string_literal: true

module Sentry
  module Agents
    module RubyLLM
      module Serializer
        module_function

        def messages(messages)
          system, non_system = Array(messages).partition { |message| message.role == :system }

          [
            system.flat_map { |message| parts(message) },
            non_system.map { |message| normalize_message(message) }
          ]
        end

        def tool_definitions(payload)
          definitions = payload[:chat].tools.values.map do |tool|
            {
              name: tool.name,
              description: tool.description,
              parameters: tool.parameters_schema
            }.compact
          end

          definitions + payload[:provider_tools]
        end

        def normalize_message(message)
          role = normalize_role(message.role)
          { role: role, parts: parts(message) }
        end

        def parts(message)
          case normalize_role(message.role)
          when "tool"
            [{ type: "tool_call_response", id: message.tool_call_id, response: message.content }]
          else
            result = []
            result << { type: "text", content: message.content } unless message.content.nil?
            message.tool_calls.each do |tool_call|
              result << {
                type: "tool_call",
                id: tool_call.id,
                name: tool_call.name,
                arguments: tool_call.arguments
              }.compact
            end
            result
          end
        end

        def normalize_role(role)
          case role.to_s
          when "human" then "user"
          when "ai" then "assistant"
          when "function" then "tool"
          else role.to_s
          end
        end
      end
    end
  end
end
