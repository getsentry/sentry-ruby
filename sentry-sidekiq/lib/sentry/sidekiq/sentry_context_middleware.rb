# frozen_string_literal: true

require "sentry/sidekiq/job_extension"
require "sentry/sidekiq/active_job_support/server_middleware"

module Sentry
  module Sidekiq
    class SentryContextServerMiddleware
      prepend ActiveJobSupport::ServerMiddleware

      SPAN_ORIGIN = JobExtension::SPAN_ORIGIN

      def self.consumer
        @consumer ||= Sentry::JobExtensions::Consumer.new(integration: Sentry::Sidekiq, origin: SPAN_ORIGIN)
      end

      def call(worker, job, queue)
        return yield unless Sentry.initialized?

        sidekiq_job = job.merge("queue" => queue)

        Sentry.clone_hub_to_current_thread
        scope = Sentry.get_current_scope
        consumer.apply_scope_data(scope, sidekiq_job, default_scope_data: job_extension.scope_data(job: sidekiq_job))
        scope.set_transaction_name(job_extension.transaction_name(job: job), source: :task)
        trace_headers = execution_trace_headers(job, sidekiq_job)
        transaction = consumer.start_transaction(
          scope, sidekiq_job,
          payload: sidekiq_job,
          trace_headers: trace_headers,
          messaging_data: -> { job_extension.consumer_messaging_data(sidekiq_job) },
          default_retry_count: job_extension.retry_info(job: sidekiq_job)[:count],
          always_continue_trace: true
        )

        begin
          perform_job(job, sidekiq_job, scope: scope) { yield }
        rescue
          consumer.finish_transaction(transaction, 500)
          raise
        end

        consumer.finish_transaction(transaction, 200)
        # don't need to use ensure here
        # if the job failed, we need to keep the scope for error handler. and the scope will be cleared there
        scope.clear
      end

      private

      def execution_trace_headers(job, sidekiq_job)
        job_extension.extract_trace_headers(job: sidekiq_job, payload: sidekiq_job)
      end

      def perform_job(job, sidekiq_job, scope:)
        yield
      end

      def consumer
        self.class.consumer
      end

      def job_extension
        Sentry::Sidekiq.job_extension
      end
    end

    class SentryContextClientMiddleware
      def self.producer
        @producer ||= Sentry::JobExtensions::Producer.new
      end

      def call(worker_class, job, queue, _redis_pool)
        return yield unless Sentry.initialized?

        if Sentry.configuration.data_collection.user_info
          user = Sentry.get_current_scope.user
          job["sentry_user"] = user unless user.empty?
        end

        if Sentry.configuration.sidekiq.propagate_traces
          headers = Sentry.get_trace_propagation_headers
          payload = Sentry::Sidekiq.job_extension.inject_trace_headers(job: job, payload: job, headers: headers)
          job.replace(producer.inject_trace_headers(job, payload, headers))
        end

        producer.record_span(
          job,
          description: worker_class.to_s,
          extension_messaging_keys: %i[system message_id],
          default_messaging_data: { system: Sentry::Sidekiq.job_extension.name, message_id: job["jid"] },
          messaging_data: { destination: queue },
          retry_count: false
        ) { yield }
      end

      private

      def producer
        self.class.producer
      end
    end
  end
end
