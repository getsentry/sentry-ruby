# frozen_string_literal: true

module Sentry
  module GoodJob
    class ErrorHandler
      # Default retry attempts for ActiveJob (matches ActiveJob::Base.retry_on default)
      DEFAULT_RETRY_ATTEMPTS = 5

      # @param ex [Exception] the exception / error that occurred
      # @param job [ActiveJob::Base] the job instance that failed
      def call(ex, job)
        return unless Sentry.initialized?

        # Skip reporting if configured to only report after all retries are exhausted
        if Sentry.configuration.good_job.report_after_job_retries && retryable?(job)
          retry_count = job.executions
          # Use default retry attempts since we can't reliably access the configured value
          max_retries = DEFAULT_RETRY_ATTEMPTS
          return if retry_count < max_retries
        end

        # Skip reporting if configured to only report dead jobs and this job can be retried
        return if Sentry.configuration.good_job.report_only_dead_jobs && retryable?(job)

        # Report to Sentry via GoodJob wrapper for testability
        # Context is already set by the job concern
        Sentry::GoodJob.capture_exception(
          ex,
          contexts: { good_job: job_context(job) },
          hint: { background: true }
        )
      end

      private

      def retryable?(job)
        # Since we can't reliably access retry configuration, we'll use a simpler approach:
        # If the job has been executed more than once, it's likely retryable
        # This is a conservative approach that works with the actual ActiveJob API
        job.executions > 1
      end

      def job_context(job)
        context = {
          job_class: job.class.name,
          job_id: job.job_id,
          queue_name: job.queue_name,
          executions: job.executions,
          enqueued_at: job.enqueued_at,
          scheduled_at: job.scheduled_at
        }

        if Sentry.configuration.good_job.include_job_arguments
          context[:arguments] = job.arguments.map(&:inspect)
        end

        context
      end
    end
  end
end
