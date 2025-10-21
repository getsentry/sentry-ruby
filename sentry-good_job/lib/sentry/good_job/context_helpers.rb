# frozen_string_literal: true

# Helper methods for adding GoodJob-specific information to Sentry context
# This works WITH sentry-rails, not against it
module Sentry
  module GoodJob
    module ContextHelpers
      # Add GoodJob-specific information to the existing Sentry Rails context
      def self.add_context(job, base_context = {})
        return base_context unless job.respond_to?(:queue_name) && job.respond_to?(:executions)

        good_job_context = {
          queue_name: job.queue_name,
          executions: job.executions,
          enqueued_at: job.enqueued_at,
          priority: job.respond_to?(:priority) ? job.priority : nil
        }

        # Note: Job arguments are handled by sentry-rails via send_default_pii configuration
        # This is controlled by Sentry.configuration.send_default_pii, not GoodJob-specific config

        # Merge with base context
        base_context.merge(good_job: good_job_context)
      end

      # Add GoodJob-specific information to the existing Sentry Rails tags
      def self.add_tags(job, base_tags = {})
        return base_tags unless job.respond_to?(:queue_name) && job.respond_to?(:executions)

        good_job_tags = {
          queue_name: job.queue_name,
          executions: job.executions
        }

        # Add priority if available
        if job.respond_to?(:priority)
          good_job_tags[:priority] = job.priority
        end

        base_tags.merge(good_job_tags)
      end

      # Enhanced context that includes both ActiveJob and GoodJob-specific data
      def self.enhanced_context(job)
        # Start with sentry-rails ActiveJob context
        active_job_context = {
          active_job: job.class.name,
          arguments: job.respond_to?(:arguments) ? job.arguments.map(&:inspect) : [],
          scheduled_at: job.scheduled_at,
          job_id: job.job_id,
          provider_job_id: job.provider_job_id,
          locale: job.locale
        }

        # Add GoodJob-specific context
        good_job_context = {
          queue_name: job.queue_name,
          executions: job.executions,
          enqueued_at: job.enqueued_at,
          priority: job.respond_to?(:priority) ? job.priority : nil
        }

        {
          active_job: active_job_context,
          good_job: good_job_context
        }
      end

      # Enhanced tags that include both ActiveJob and GoodJob-specific data
      def self.enhanced_tags(job)
        base_tags = {
          job_id: job.job_id,
          provider_job_id: job.provider_job_id
        }

        good_job_tags = {
          queue_name: job.queue_name,
          executions: job.executions
        }

        if job.respond_to?(:priority)
          good_job_tags[:priority] = job.priority
        end

        base_tags.merge(good_job_tags)
      end
    end
  end
end
