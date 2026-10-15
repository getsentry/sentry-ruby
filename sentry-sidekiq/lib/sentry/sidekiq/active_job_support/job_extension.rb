# frozen_string_literal: true

module Sentry
  module Sidekiq
    module ActiveJobSupport
      module JobExtension
        ACTIVE_JOB_ADAPTER = "ActiveJob::QueueAdapters::SidekiqAdapter"
        SIDEKIQ_JOB_KEY = "_sentry_sidekiq_job"

        def handles?(job)
          super || active_job?(job)
        end

        def scope_data(job:)
          return super unless active_job?(job)

          sidekiq_job = handed_over_sidekiq_job(job)
          sidekiq_job ? super(job: sidekiq_job) : {}
        end

        def messaging_data(job:)
          return super unless active_job?(job)

          sidekiq_job = handed_over_sidekiq_job(job)
          return {} unless sidekiq_job

          super(job: sidekiq_job).merge(body_size: body_size(sidekiq_job)).compact
        end

        def retry_info(job:)
          return super unless active_job?(job)

          sidekiq_job = handed_over_sidekiq_job(job)
          super(job: sidekiq_job) if sidekiq_job
        end

        def extract_trace_headers(job:, payload:)
          return super if sidekiq_job?(payload)

          sidekiq_job = sidekiq_job_in(payload)
          super(job: job, payload: sidekiq_job) if sidekiq_job
        end

        def transaction_name(job:)
          active_job?(job) ? "#{self.class::SIDEKIQ_NAME}/#{job.class.name}" : super
        end

        def span_origin(job:)
          active_job?(job) ? self.class::SPAN_ORIGIN : super
        end

        def integration(job:)
          active_job?(job) ? Sentry::Sidekiq : super
        end

        def report_retried_exception?(job:, exception:)
          active_job?(job) ? false : super
        end

        def performed_by_active_job?(sidekiq_job)
          !!sidekiq_job["wrapped"] && active_job_owns_adapter?
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

        def active_job?(job)
          return false unless defined?(::ActiveJob::Base) && job.is_a?(::ActiveJob::Base)

          job.class.queue_adapter.class.name == ACTIVE_JOB_ADAPTER
        end

        def active_job_owns_adapter?
          return false unless defined?(::Sentry::Rails::ActiveJobExtensions)
          return false unless ::Sentry::Rails.respond_to?(:active_job_owns_adapter?)

          ::Sentry::Rails.active_job_owns_adapter?(ACTIVE_JOB_ADAPTER)
        end

        def handed_over_sidekiq_job(job)
          return unless active_job?(job) && job.respond_to?(:_sentry_job_data)

          sidekiq_job_in(job._sentry_job_data)
        end

        def sidekiq_job_in(active_job_payload)
          return unless active_job_payload.is_a?(Hash)

          sidekiq_job = active_job_payload[SIDEKIQ_JOB_KEY]
          sidekiq_job if sidekiq_job?(sidekiq_job)
        end
      end
    end
  end
end
