# frozen_string_literal: true

require "sentry/sidekiq/retry_policy"

module Sentry
  module Sidekiq
    class FailureReporting
      def initialize(retry_policy: RetryPolicy.build)
        @retry_policy = retry_policy
      end

      def report?(job, sidekiq_config = nil)
        config = Sentry.configuration.sidekiq
        retry_limit = @retry_policy.limit(job, sidekiq_config)

        return false if config.report_after_job_retries && retries_pending?(job, retry_limit)
        return false if config.report_only_dead_jobs && job_value(job, "dead") == false
        return false if below_attempt_threshold?(job, retry_limit)

        true
      end

      private

      def retries_pending?(job, retry_limit)
        return false unless @retry_policy.retryable?(job)

        retry_count = job_value(job, "retry_count")
        retry_count.nil? || retry_count < retry_limit - 1
      end

      def below_attempt_threshold?(job, retry_limit)
        attempt_threshold = job_value(job, "attempt_threshold")
        return false unless attempt_threshold && @retry_policy.retryable?(job)

        [attempt_threshold.to_i, retry_limit + 1].min > attempt(job)
      end

      def attempt(job)
        retry_count = job_value(job, "retry_count")
        retry_count.nil? ? 1 : retry_count.to_i + 2
      end

      def job_value(job, key)
        job && job[key]
      end
    end
  end
end
