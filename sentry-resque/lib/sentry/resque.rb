# frozen_string_literal: true

require "resque"

module Sentry
  module Resque
    def perform
      return super unless Sentry.initialized?

      Sentry.with_scope do |scope|
        begin
          contexts = generate_contexts
          scope.set_contexts(**contexts)
          scope.set_tags("resque.queue" => queue)

          scope.set_transaction_name(contexts.dig(:"Active-Job", :job_class) || contexts.dig(:"Resque", :job_class))
          transaction = Sentry.start_transaction(name: scope.transaction_name, op: "resque")
          scope.set_span(transaction) if transaction

          super

          finish_transaction(transaction, 200)
        rescue Exception => exception
          ::Sentry::Resque.capture_exception(exception, hint: { background: false })
          finish_transaction(transaction, 500)
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

    def finish_transaction(transaction, status)
      return unless transaction

      transaction.set_http_status(status)
      transaction.finish
    end
  end
end

Resque::Job.send(:prepend, Sentry::Resque)
