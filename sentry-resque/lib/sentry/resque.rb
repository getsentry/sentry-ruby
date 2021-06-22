require "resque"

module Sentry
  module Resque
    def perform
      return super unless Sentry.initialized?

      Sentry.with_scope do |scope|
        begin
          scope.set_contexts(**generate_contexts)
          scope.set_tags("resque.queue" => queue)

          super
        rescue Exception => exception
          ::Sentry::Resque.capture_exception(exception, hint: { background: false })
          raise
        end
      end
    end

    def generate_contexts
      context = {}

      if payload["class"] == "ActiveJob::QueueAdapters::ResqueAdapter::JobWrapper"
        active_job_payload = payload["args"].first

        context[:"Active-Job"] = {
          job_class: active_job_payload["job_class"],
          job_id: active_job_payload["job_id"],
          arguments: active_job_payload["arguments"],
          executions: active_job_payload["executions"],
          exception_executions: active_job_payload["exception_executions"],
          locale: active_job_payload["locale"],
          enqueued_at: active_job_payload["enqueued_at"],
          queue: queue,
          worker: worker.to_s
        }
      else
        context[:"Resque"] = {
          job_class: payload["class"],
          arguments: payload["args"],
          queue: queue,
          worker: worker.to_s
        }
      end

      context
    end
  end
end

Resque::Job.send(:prepend, Sentry::Resque)
