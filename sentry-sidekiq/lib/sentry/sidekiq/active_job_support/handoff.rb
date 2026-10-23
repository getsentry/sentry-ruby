# frozen_string_literal: true

module Sentry
  module Sidekiq
    module ActiveJobSupport
      module Handoff
        ACTIVE_JOB_ADAPTER = "ActiveJob::QueueAdapters::SidekiqAdapter"
        SIDEKIQ_JOB_KEY = "_sentry_sidekiq_job"

        def performed_by_active_job?(sidekiq_job)
          !!sidekiq_job["wrapped"] && active_job_handoff?
        end

        def active_job_args(sidekiq_job, scope:)
          payload, *arguments = sidekiq_job["args"]
          return sidekiq_job["args"] unless payload.is_a?(Hash)

          sentry_data = (payload["_sentry"] || {}).merge("delivery_queue" => sidekiq_job["queue"])
          sentry_data["execution_scope_id"] = scope.object_id
          [payload.merge(
            SIDEKIQ_JOB_KEY => sidekiq_job,
            "_sentry" => sentry_data
          ), *arguments]
        end

        private

        def handles_active_job?(job)
          return false unless defined?(::ActiveJob::Base) && job.is_a?(::ActiveJob::Base)

          job.class.queue_adapter.class.name == ACTIVE_JOB_ADAPTER && active_job_handoff?
        end

        def active_job_handoff?
          active_job_owns_adapter? && Sentry.configuration.sidekiq.active_job_integration == :rails
        end

        def active_job_owns_adapter?
          return false unless defined?(::Sentry::Rails::ActiveJobExtensions)
          return false unless ::Sentry::Rails.respond_to?(:active_job_owns_adapter?)

          ::Sentry::Rails.active_job_owns_adapter?(ACTIVE_JOB_ADAPTER)
        end

        def sidekiq_job_in(active_job_payload)
          return unless active_job_payload.is_a?(Hash)

          sidekiq_job = active_job_payload[SIDEKIQ_JOB_KEY]
          sidekiq_job if sidekiq_job.is_a?(Hash) && sidekiq_job.key?("jid")
        end
      end
    end
  end
end
