module Raven
  class Rails
    module ActiveJobExtensions
      ALREADY_SUPPORTED_SENTRY_ADAPTERS = %w(
        ActiveJob::QueueAdapters::SidekiqAdapter
        ActiveJob::QueueAdapters::DelayedJobAdapter
      ).freeze

      def self.included(base)
        base.class_eval do
          around_perform do |job, block|
            if already_supported_by_specific_integration?(job)
              block.call
            else
              capture_and_reraise_with_sentry(job, block)
            end
          end
        end
      end

      def capture_and_reraise_with_sentry(job, block)
        block.call
      rescue Exception => e # rubocop:disable Lint/RescueException
        rescue_handler_result = rescue_with_handler(e)
        return rescue_handler_result if rescue_handler_result

        Raven.capture_exception(e, :extra => raven_context(job))
        raise e
      ensure
        Context.clear!
        BreadcrumbBuffer.clear!
      end

      def already_supported_by_specific_integration?(job)
        if ::Rails.version.to_f < 5.0
          ALREADY_SUPPORTED_SENTRY_ADAPTERS.include?(job.class.queue_adapter.to_s)
        else
          ALREADY_SUPPORTED_SENTRY_ADAPTERS.include?(job.class.queue_adapter.class.to_s)
        end
      end

      def raven_context(job)
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
  include Raven::Rails::ActiveJobExtensions
end
