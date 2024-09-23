# frozen_string_literal: true

require 'langchain'

module Sentry
  module AI
    module Langchain
      def self.patch_langchain_llms
        # List of all LLM classes
        llm_classes = [
          ::Langchain::LLM::AI21,
          ::Langchain::LLM::Anthropic,
          ::Langchain::LLM::Azure,
          ::Langchain::LLM::Cohere,
          ::Langchain::LLM::GooglePalm,
          ::Langchain::LLM::GoogleVertexAI,
          ::Langchain::LLM::GoogleGemini,
          ::Langchain::LLM::HuggingFace,
          ::Langchain::LLM::LlamaCpp,
          ::Langchain::LLM::OpenAI,
          ::Langchain::LLM::Replicate
        ]

        llm_classes.each do |llm_class|
          patch_llm_class(llm_class)
        end
      end

      def self.patch_llm_class(llm_class)
        llm_class.prepend(LangchainLLMPatch)
      end

      module LangchainLLMPatch
        def chat(...)
          wrap_with_sentry("chat") { super(...) }
        end

        def complete(...)
          wrap_with_sentry("complete") { super(...) }
        end

        def embed(...)
          wrap_with_sentry("embed") { super(...) }
        end

        def summarize(...)
          wrap_with_sentry("summarize") { super(...) }
        end

        private

        def wrap_with_sentry(call_type)
          transaction = Sentry.get_current_scope.get_transaction

          Sentry.capture_message("LangChain LLM #{call_type} call initiated for #{self.class.name}", level: 'info')

          if transaction
            span = transaction.start_child(
              op: "ai.#{call_type}.langchain",
              description: "LangChain LLM #{call_type.capitalize} Call for #{self.class.name}",
              origin: "auto.ai.langchain"
            )

            span.set_data("ai.model_id", "#{self.class.name}::#{@defaults[:chat_completion_model_name]}")

            # Add additional SPANDATA fields
            span.set_data("ai.frequency_penalty", @defaults[:frequency_penalty])
            span.set_data("ai.presence_penalty", @defaults[:presence_penalty])
            span.set_data("ai.input_messages", @defaults[:messages])
            span.set_data("ai.metadata", @defaults[:metadata])
            span.set_data("ai.tags", @defaults[:tags])
            span.set_data("ai.streaming", @defaults[:stream])
            span.set_data("ai.temperature", @defaults[:temperature])
            span.set_data("ai.top_p", @defaults[:top_p])
            span.set_data("ai.top_k", @defaults[:top_k])
            span.set_data("ai.function_call", @defaults[:function_call])
            span.set_data("ai.tools", @defaults[:tools])
            span.set_data("ai.response_format", @defaults[:response_format])
            span.set_data("ai.logit_bias", @defaults[:logit_bias])
            span.set_data("ai.preamble", @defaults[:preamble])
            span.set_data("ai.raw_prompting", @defaults[:raw_prompting])
            span.set_data("ai.seed", @defaults[:seed])

            Sentry.capture_message("LLM span created for #{self.class.name}", level: 'info')

            begin
              result = yield
              response_text = result.respond_to?(:completion) ? result.completion : result.to_s
              span.set_data("ai.responses", [response_text])

              # Workaround: calculate token usage based on characters / 4
              prompt_tokens = (@defaults[:messages].to_s.length / 4.0).ceil
              completion_tokens = (response_text.length / 4.0).ceil
              total_tokens = prompt_tokens + completion_tokens
              Sentry::AI::Monitoring.record_token_usage(transaction,
                prompt_tokens: prompt_tokens, 
                completion_tokens: completion_tokens,
                total_tokens: total_tokens
              )

              Sentry.capture_message("LLM call completed successfully for #{self.class.name}", level: 'info')
              result
            rescue => e
              span.set_status("internal_error")
              Sentry.capture_exception(e, level: 'error')
              Sentry.capture_message("Error in LLM call for #{self.class.name}: #{e.message}", level: 'error')
              raise
            ensure
              span.finish
              Sentry.capture_message("LLM span finished for #{self.class.name}", level: 'info')
            end
          else
            Sentry.capture_message("No active transaction found for LLM call in #{self.class.name}", level: 'warning')
            yield
          end
        end
      end
    end
  end
end

Sentry.register_integration(:langchain, Sentry::VERSION)
Sentry.capture_message("Sentry LangChain integration registered", level: 'info')
