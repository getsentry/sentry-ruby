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
            capture_and_reraise_with_sentry(job, block)
          end
        end
      end

      def capture_and_reraise_with_sentry(job, block)
        block.call
      rescue Exception => exception # rubocop:disable Lint/RescueException
        return if rescue_with_handler(exception)
        unless already_supported_by_specific_integration?(job)
          Raven.capture_exception(exception, :extra => raven_context(job))
        end
        raise exception
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
