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
        if Sentry.configuration.good_job.report_after_job_retries
          if retryable?(job)
            # For retryable jobs, only report after max retries are reached
            return unless has_exhausted_retries?(job)
          end
          # For non-retryable jobs, report immediately (they're dead on first failure)
        end

        # Skip reporting if configured to only report dead jobs
        if Sentry.configuration.good_job.report_only_dead_jobs
          if retryable?(job)
            # For retryable jobs, never report (they're not dead yet)
            return
          end
          # For non-retryable jobs, report immediately (they're dead on first failure)
        end

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
        # Determine if a job is likely retryable based on execution patterns
        # This is a heuristic approach since we can't reliably access retry configuration

        # If the job has been executed multiple times, it's likely retryable
        # This covers the common case where jobs are configured to retry
        job.executions > 1
      end

      def has_exhausted_retries?(job)
        # Determine if a job has likely exhausted its retries
        # This is a heuristic based on execution count and reasonable retry limits

        # If a job has been executed many times (more than typical retry limits),
        # it's likely exhausted its retries and is now dead
        job.executions > DEFAULT_RETRY_ATTEMPTS
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
