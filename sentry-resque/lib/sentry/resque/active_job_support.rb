# frozen_string_literal: true

module Sentry
  module Resque
    module ActiveJobSupport
      ACTIVE_JOB_ADAPTER = "ActiveJob::QueueAdapters::ResqueAdapter"
      ACTIVE_JOB_WRAPPER = "ActiveJob::QueueAdapters::ResqueAdapter::JobWrapper"
      RESQUE_JOB_KEY = "_sentry_resque_job"

      def performed_by_active_job?(payload)
        payload["class"] == ACTIVE_JOB_WRAPPER &&
          active_job_handoff?
      end

      def active_job_args(queue:, worker:, payload:)
        active_job_payload, *arguments = payload["args"]
        return payload["args"] unless active_job_payload.is_a?(Hash)

        resque_job = { "queue" => queue, "worker" => worker.to_s, "payload" => payload.dup }
        [active_job_payload.merge(RESQUE_JOB_KEY => resque_job), *arguments]
      end

      private

      def handles_active_job?(job)
        return false unless defined?(::ActiveJob::Base) && job.is_a?(::ActiveJob::Base)

        job.class.queue_adapter.class.name == ACTIVE_JOB_ADAPTER && active_job_handoff?
      end

      def active_job_handoff?
        active_job_owns_adapter? && Sentry.configuration.resque.active_job_integration == :rails
      end

      def active_job_owns_adapter?
        return false unless defined?(::Sentry::Rails::ActiveJobExtensions)
        return false unless ::Sentry::Rails.respond_to?(:active_job_owns_adapter?)

        ::Sentry::Rails.active_job_owns_adapter?(ACTIVE_JOB_ADAPTER)
      end
    end
  end
end
