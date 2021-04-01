# frozen_string_literal: true
require "delayed_job"

module Sentry
  module DelayedJob
    class Plugin < ::Delayed::Plugin
      # need to symbolize strings as keyword arguments in Ruby 2.4~2.6
      DELAYED_JOB_CONTEXT_KEY = :"Delayed-Job"
      ACTIVE_JOB_CONTEXT_KEY = :"Active-Job"

      callbacks do |lifecycle|
        lifecycle.around(:invoke_job) do |job, *args, &block|
          next block.call(job, *args) unless Sentry.initialized?

          Sentry.with_scope do |scope|
            scope.set_contexts(**generate_contexts(job))
            scope.set_tags("delayed_job.queue" => job.queue, "delayed_job.id" => job.id.to_s)

            begin
              block.call(job, *args)
            rescue Exception => e
              capture_exception(e, job)

              raise
            end
          end
        end
      end

      def self.generate_contexts(job)
        context = {}

        context[DELAYED_JOB_CONTEXT_KEY] = {
          id: job.id.to_s,
          priority: job.priority,
          attempts: job.attempts,
          run_at: job.run_at,
          locked_at: job.locked_at,
          locked_by: job.locked_by,
          queue: job.queue,
          created_at: job.created_at,
          last_error: job.last_error&.byteslice(0..1000),
          handler: job.handler&.byteslice(0..1000)
        }

        if job.payload_object.respond_to?(:job_data)
          context[ACTIVE_JOB_CONTEXT_KEY] = {}

          job.payload_object.job_data.each do |key, value|
            context[ACTIVE_JOB_CONTEXT_KEY][key.to_sym] = value
          end
        end

        context
      end

      def self.capture_exception(exception, job)
        Sentry::DelayedJob.capture_exception(exception, hint: { background: false }) if report?(job)
      end

      def self.report?(job)
        return true unless Sentry.configuration.delayed_job.report_after_job_retries

        # We use the predecessor because the job's attempts haven't been increased to the new
        # count at this point.
        job.attempts >= Delayed::Worker.max_attempts.pred
      end
    end
  end
end

Delayed::Worker.plugins << Sentry::DelayedJob::Plugin
