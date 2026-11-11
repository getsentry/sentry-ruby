# frozen_string_literal: true

module Sentry
  module Sidekiq
    module ActiveJobSupport
      ACTIVE_JOB_ADAPTER = "ActiveJob::QueueAdapters::SidekiqAdapter"

      # Prepended to {SentryContextServerMiddleware} when sentry-rails reports
      # ActiveJob jobs on Sidekiq. For those jobs it only isolates the hub and
      # continues the job's trace, leaving the reporting to sentry-rails.
      module ServerMiddleware
        def call(worker, job, queue)
          return super unless ActiveJobSupport.handles?(job)

          if Sentry.initialized?
            Sentry.clone_hub_to_current_thread
            Sentry.continue_trace(job["trace_propagation_headers"] || {})
          end

          yield
        end
      end
    end
  end
end
