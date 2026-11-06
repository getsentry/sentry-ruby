# frozen_string_literal: true

require "sentry/sidekiq/job_extension"

module Sentry
  module Sidekiq
    # Sidekiq server middleware that runs each job in its own scope and
    # `queue.process` transaction, using the extension for the job.
    #
    # @see Sentry::Sidekiq.job_extension_for
    class SentryContextServerMiddleware
      OP_NAME = Sentry::JobExtensions::Extension::PROCESS_OP
      SPAN_ORIGIN = JobExtension::SPAN_ORIGIN

      # @param extension [JobExtension] the extension for plain Sidekiq jobs
      def initialize(extension = Sentry::Sidekiq.job_extension)
        @extension = extension
      end

      def call(worker, job, queue)
        return yield unless Sentry.initialized?

        sidekiq_job = job.merge("queue" => queue)

        Sentry.clone_hub_to_current_thread
        scope = Sentry.get_current_scope
        extension = Sentry::Sidekiq.job_extension_for(sidekiq_job, default: @extension)
        scope.generate_propagation_context unless continues_trace?(extension, sidekiq_job)
        transaction = extension.start_job(scope: scope, job: sidekiq_job)

        begin
          yield
        rescue
          extension.finish_job(transaction: transaction, status: 500)
          raise
        end

        extension.finish_job(transaction: transaction, status: 200)
        # don't need to use ensure here
        # if the job failed, we need to keep the scope for error handler. and the scope will be cleared there
        scope.clear
      end

      private

      def continues_trace?(extension, job)
        extension.safely("extract trace headers", fallback: false) { !Hash(extension.extract_trace_headers(job: job)).empty? }
      end
    end

    # Sidekiq client middleware that passes the user and trace to enqueued jobs
    # and records their `queue.publish` spans.
    class SentryContextClientMiddleware
      # @param extension [JobExtension]
      def initialize(extension = Sentry::Sidekiq.job_extension)
        @extension = extension
      end

      def call(worker_class, job, queue, _redis_pool)
        return yield unless Sentry.initialized?

        if Sentry.configuration.data_collection.user_info
          user = Sentry.get_current_scope.user
          job["sentry_user"] = user unless user.empty?
        end

        if Sentry.configuration.sidekiq.propagate_traces
          headers = Sentry.get_trace_propagation_headers
          injected = @extension.safely("inject trace headers", fallback: job) { @extension.inject_trace_headers(job: job, payload: job, headers: headers) }
          job.replace(injected) if injected.is_a?(Hash)
        end

        @extension.instrument_enqueue(job: job.merge("queue" => queue)) { yield }
      end
    end
  end
end
