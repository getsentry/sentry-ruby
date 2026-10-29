# frozen_string_literal: true

module Sentry
  module Sidekiq
    module ActiveJobSupport
      module ServerMiddleware
        private

        def execution_trace_headers(job, sidekiq_job)
          if job_extension.performed_by_active_job?(job) && job["args"].first.is_a?(Hash)
            headers = job["args"].first.dig("_sentry", "trace_propagation_headers")
            return headers if headers && !headers.empty?
          end

          super
        end

        def perform_job(job, sidekiq_job, scope:)
          return super unless job_extension.performed_by_active_job?(job)

          args = job["args"]
          begin
            job["args"] = job_extension.active_job_args(sidekiq_job, scope: scope)
            super
          ensure
            job["args"] = args
          end
        end
      end
    end
  end
end
