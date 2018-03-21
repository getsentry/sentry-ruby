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
        begin
          return if rescue_with_handler(exception)

          unless already_supported_by_specific_integration?(job)
            Raven.capture_exception(exception, :extra => raven_context(job))
          end
        rescue Exception => secondary_exception
          # it's possible for rescue_with_handler to (re)raise the error or error on its own.

          # in this corner case...
          unless already_supported_by_specific_integration?(job)
            # we first log the original exception which blew up
            Raven.capture_exception(exception, :extra => raven_context(job))

            # then we log the exception which was raised trying to handle the original
            unless exception == secondary_exception
              # we only should log the second exception if its different than the first
              Raven.capture_exception(secondary_exception, :extra => raven_context(job))
            end
          end

          # finally, raise the secondary exception, because that's what /should/ bubble up
          raise secondary_exception
        end

        raise exception
      ensure
        Context.clear!
        BreadcrumbBuffer.clear!
      end

      def already_supported_by_specific_integration?(job)
        ALREADY_SUPPORTED_SENTRY_ADAPTERS.include?(job.class.queue_adapter.to_s)
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
