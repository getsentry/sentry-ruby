# frozen_string_literal: true

require "resque"

module Sentry
  module Resque
    def perform
      if Sentry.initialized?
        SentryReporter.record(queue, worker, payload) do
          super
        end
      else
        super
      end
    end

    class SentryReporter
      class << self
        def record(queue, worker, payload, &block)
          Sentry.with_scope do |scope|
            begin
              contexts = generate_contexts(queue, worker, payload)
              scope.set_contexts(**contexts)
              scope.set_tags("resque.queue" => queue)

              name = contexts.dig(:"Active-Job", :job_class) || contexts.dig(:"Resque", :job_class)
              scope.set_transaction_name(name, source: :task)
              transaction = Sentry.start_transaction(name: scope.transaction_name, source: scope.transaction_source, op: "queue.resque")
              scope.set_span(transaction) if transaction

              yield

              finish_transaction(transaction, 200)
            rescue Exception => exception
              klass = payload['class'].constantize

              raise if Sentry.configuration.resque.report_after_job_retries &&
                       defined?(::Resque::Plugins::Retry) == 'constant' &&
                       klass.is_a?(::Resque::Plugins::Retry) &&
                       !klass.retry_limit_reached?

              ::Sentry::Resque.capture_exception(exception, hint: { background: false })
              finish_transaction(transaction, 500)
              raise
            end
          end
        end

        def generate_contexts(queue, worker, payload)
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
  end
end

Resque::Job.send(:prepend, Sentry::Resque)
