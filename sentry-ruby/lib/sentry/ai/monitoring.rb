# frozen_string_literal: true

module Sentry
  module AI
    module Monitoring
      DEFAULT_PIPELINE_NAME = "default_ai_pipeline"

      class << self
        def ai_track(description, **span_kwargs)
          lambda do |original_method|
            define_method(original_method.name) do |*args, **kwargs, &block|
              transaction = Sentry.get_current_scope.get_transaction
              curr_pipeline = Monitoring.ai_pipeline_name
              op = span_kwargs[:op] || (curr_pipeline ? "ai.run" : "ai.pipeline")

              if transaction
                span = transaction.start_child(
                  op: op,
                  description: description,
                  origin: "auto.ai.monitoring",
                  **span_kwargs
                )

                kwargs[:sentry_tags]&.each { |k, v| span.set_tag(k, v) }
                kwargs[:sentry_data]&.each { |k, v| span.set_data(k, v) }

                span.set_data("ai.pipeline.name", curr_pipeline) if curr_pipeline

                begin
                  if curr_pipeline
                    result = original_method.bind(self).call(*args, **kwargs, &block)
                  else
                    Monitoring.ai_pipeline_name = description
                    result = original_method.bind(self).call(*args, **kwargs, &block)
                  end
                rescue => e
                  Sentry.capture_exception(e)
                  raise
                ensure
                  Monitoring.ai_pipeline_name = nil unless curr_pipeline
                  span.finish
                end

                result
              else
                original_method.bind(self).call(*args, **kwargs, &block)
              end
            end
          end
        end

        def record_token_usage(span, prompt_tokens: nil, completion_tokens: nil, total_tokens: nil)
          ai_pipeline_name = Monitoring.ai_pipeline_name
          span.set_data("ai.pipeline.name", ai_pipeline_name) if ai_pipeline_name
          span.set_measurement("ai_prompt_tokens_used", value: prompt_tokens) if prompt_tokens
          span.set_data("ai.prompt_tokens.used", value: prompt_tokens) if prompt_tokens
          span.set_measurement("ai_completion_tokens_used", value: completion_tokens) if completion_tokens
          span.set_data("ai.completion_tokens.used", value: completion_tokens) if completion_tokens

          if total_tokens.nil? && prompt_tokens && completion_tokens
            total_tokens = prompt_tokens + completion_tokens
          end

          span.set_measurement("ai_total_tokens_used", value: total_tokens) if total_tokens
          span.set_data("ai.total_tokens.used", value: total_tokens) if total_tokens
        end

        def ai_pipeline_name
          Thread.current[:sentry_ai_pipeline_name] ||= DEFAULT_PIPELINE_NAME
        end

        def ai_pipeline_name=(name)
          Thread.current[:sentry_ai_pipeline_name] = name
        end
      end
    end
  end
end