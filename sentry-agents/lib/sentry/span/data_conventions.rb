# frozen_string_literal: true

module Sentry
  class Span
    module DataConventions
      GEN_AI_OPERATION_NAME = "gen_ai.operation.name"
      GEN_AI_PROVIDER_NAME = "gen_ai.provider.name"
      GEN_AI_REQUEST_MODEL = "gen_ai.request.model"
      GEN_AI_REQUEST_TEMPERATURE = "gen_ai.request.temperature"
      GEN_AI_REQUEST_MAX_TOKENS = "gen_ai.request.max_tokens"
      GEN_AI_REQUEST_STREAM = "gen_ai.request.stream"
      GEN_AI_REQUEST_REASONING_LEVEL = "gen_ai.request.reasoning.level"
      GEN_AI_INPUT_MESSAGES = "gen_ai.input.messages"
      GEN_AI_SYSTEM_INSTRUCTIONS = "gen_ai.system_instructions"
      GEN_AI_TOOL_DEFINITIONS = "gen_ai.tool.definitions"
      GEN_AI_TOOL_NAME = "gen_ai.tool.name"
      GEN_AI_TOOL_CALL_ARGUMENTS = "gen_ai.tool.call.arguments"
      GEN_AI_TOOL_CALL_RESULT = "gen_ai.tool.call.result"
      GEN_AI_PIPELINE_NAME = "gen_ai.pipeline.name"
      GEN_AI_AGENT_NAME = "gen_ai.agent.name"
      GEN_AI_RESPONSE_MODEL = "gen_ai.response.model"
      GEN_AI_RESPONSE_FINISH_REASONS = "gen_ai.response.finish_reasons"
      GEN_AI_OUTPUT_MESSAGES = "gen_ai.output.messages"
      GEN_AI_USAGE_INPUT_TOKENS = "gen_ai.usage.input_tokens"
      GEN_AI_USAGE_OUTPUT_TOKENS = "gen_ai.usage.output_tokens"
      GEN_AI_USAGE_CACHE_READ_INPUT_TOKENS = "gen_ai.usage.cache_read.input_tokens"
      GEN_AI_USAGE_CACHE_CREATION_INPUT_TOKENS = "gen_ai.usage.cache_creation.input_tokens"
      GEN_AI_USAGE_REASONING_OUTPUT_TOKENS = "gen_ai.usage.reasoning.output_tokens"
    end
  end
end
