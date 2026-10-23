# frozen_string_literal: true

require "resque"

module Sentry
  module Resque
    def perform
      if !Sentry.initialized?
        super
      elsif Sentry::Resque.performed_by_active_job?(payload)
        perform_with_active_job_hand_off { super }
      else
        SentryReporter.record(queue, worker, payload) do
          super
        end
      end
    end

    private

    def perform_with_active_job_hand_off
      start_timestamp = Sentry.utc_now.to_f
      args = payload["args"]
      begin
        payload["args"] = Sentry::Resque.active_job_args(queue: queue, worker: worker, payload: payload)
        yield
      ensure
        payload["args"] = args
      end
    rescue Exception => exception
      unless Sentry.exception_captured?(exception)
        SentryReporter.capture_exception(queue, worker, payload, exception, start_timestamp: start_timestamp)
      end
      raise
    end

    class SentryReporter
      SPAN_ORIGIN = "auto.queue.resque"

      class << self
        def capture_exception(queue, worker, payload, exception, start_timestamp:)
          Sentry.with_scope do |scope|
            apply_job_scope(scope, queue, worker, payload)
            job_data = payload["args"].first
            options = {
              name: scope.transaction_name,
              source: scope.transaction_source,
              op: "queue.process",
              origin: SPAN_ORIGIN,
              start_timestamp: start_timestamp
            }
            continued = Sentry.continue_trace(job_data.dig("_sentry", "trace_propagation_headers") || {}, **options)
            transaction = Sentry.start_transaction(transaction: continued, **options)
            if transaction
              scope.set_span(transaction)
              transaction.set_data(Span::DataConventions::MESSAGING_SYSTEM, "resque")
              transaction.set_data(Span::DataConventions::MESSAGING_MESSAGE_ID, job_data["job_id"])
              transaction.set_data(Span::DataConventions::MESSAGING_DESTINATION_NAME, queue)
            end

            ::Sentry::Resque.capture_exception(exception, hint: { background: false })
            finish_transaction(transaction, 500)
          end
        end

        def record(queue, worker, payload, &block)
          Sentry.with_scope do |scope|
            begin
              apply_job_scope(scope, queue, worker, payload)
              transaction = Sentry.start_transaction(
                name: scope.transaction_name,
                source: scope.transaction_source,
                op: "queue.resque",
                origin: SPAN_ORIGIN
              )

              scope.set_span(transaction) if transaction

              yield

              finish_transaction(transaction, 200)
            rescue Exception => exception
              raise_if_retries_remain(payload["class"], exception)

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

        private

        def apply_job_scope(scope, queue, worker, payload)
          contexts = generate_contexts(queue, worker, payload)
          scope.set_contexts(**contexts)
          scope.set_tags("resque.queue" => queue)

          name = contexts.dig(:"Active-Job", :job_class) || contexts.dig(:"Resque", :job_class)
          scope.set_transaction_name(name, source: :task)
        end

        def raise_if_retries_remain(klass, exception)
          return unless Sentry.configuration.resque.report_after_job_retries &&
            defined?(::Resque::Plugins::Retry) == "constant"
          klass = klass.constantize if klass.respond_to?(:constantize) # Needed for Ruby < 2.7 && Rails < 7.0
          klass = Object.const_get(klass) unless klass.is_a?(Class)

          raise exception if klass.is_a?(::Resque::Plugins::Retry) && !klass.retry_limit_reached?
        end
      end
    end
  end
end

Resque::Job.send(:prepend, Sentry::Resque)
