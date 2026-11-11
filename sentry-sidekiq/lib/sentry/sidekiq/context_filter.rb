# frozen_string_literal: true

module Sentry
  module Sidekiq
    class ContextFilter
      SIDEKIQ_NAME = "Sidekiq"

      attr_reader :context

      def initialize(context)
        @context = context
      end

      def filtered
        filtered_context = context.dup

        if job_entry = filtered_context.delete(:job)
          job_entry.each do |k, v|
            filtered_context[k] = v
          end
        end

        # Sidekiq 7.0 started adding `_config` to the context, which is not easily serialisable
        # And it's presence could be confusing so it's better to remove it until we decided to add it for a reason
        filtered_context.delete(:_config)
        filtered_context
      end

      def transaction_name
        job = context["class"] ? context : context[:job]
        return Sentry::Sidekiq.job_extension_for(job).transaction_name(job: job) if job.is_a?(Hash) && job["class"]

        context[:event] ? "#{SIDEKIQ_NAME}/#{context[:event]}" : SIDEKIQ_NAME
      end
    end
  end
end
