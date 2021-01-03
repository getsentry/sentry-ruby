module Sentry
  module Rails
    module ActiveJobExtensions
      ALREADY_SUPPORTED_SENTRY_ADAPTERS = %w(
        ActiveJob::QueueAdapters::SidekiqAdapter
      ).freeze

      def self.included(base)
        base.class_eval do
          around_perform do |job, block|
            if already_supported_by_specific_integration?(job)
              block.call
            else
              Sentry.with_scope do
                capture_and_reraise_with_sentry(job, block)
              end
            end
          end
        end
      end

      def capture_and_reraise_with_sentry(job, block)
        block.call
      rescue Exception => e # rubocop:disable Lint/RescueException
        rescue_handler_result = rescue_with_handler(e)
        return rescue_handler_result if rescue_handler_result

        Sentry::Rails.capture_exception(e, extra: sentry_context(job))
        raise e
      end

      def already_supported_by_specific_integration?(job)
        ALREADY_SUPPORTED_SENTRY_ADAPTERS.include?(job.class.queue_adapter.class.to_s)
      end

      def sentry_context(job)
        ctx = {
          :active_job => job.class.name,
          :arguments => job.arguments,
          :scheduled_at => job.scheduled_at,
          :job_id => job.job_id,
          :locale => job.locale
        }
        # Add provider_job_id details if Rails 5
        if job.respond_to?(:provider_job_id)
          ctx[:provider_job_id] = job.provider_job_id
        end

        ctx
      end
    end
  end
end

class ActiveJob::Base
  include Sentry::Rails::ActiveJobExtensions
end
