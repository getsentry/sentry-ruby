# frozen_string_literal: true

require "sentry/rails/active_job_extension"
require "sentry/resque/active_job_support"

module Sentry
  module Resque
    class ActiveJobExtension < Sentry::Rails::ActiveJobExtension
      include ActiveJobSupport

      SPAN_ORIGIN = "auto.queue.resque"

      def initialize
        super(name: "resque")
      end

      def handles?(job)
        handles_active_job?(job)
      end

      def scope_data(job:)
        return super unless handles_active_job?(job)

        job_data = active_job_data(job) || {}
        resque_job = handed_over_resque_job(job_data)
        queue = resque_job.fetch("queue", job.queue_name)
        context = {
          job_class: job.class.name,
          job_id: job.job_id,
          executions: job_data["executions"],
          exception_executions: job_data["exception_executions"],
          locale: job_data["locale"],
          enqueued_at: job_data["enqueued_at"],
          queue: queue
        }
        context[:arguments] = job_data["arguments"] if Sentry.configuration.data_collection.queues
        context[:worker] = resque_job["worker"] if resque_job.key?("worker")

        { contexts: { "Active-Job": context }, tags: { "resque.queue" => queue } }
      end

      def messaging_data(job:)
        return super unless handles_active_job?(job)

        job_data = active_job_data(job)
        resque_job = handed_over_resque_job(job_data)
        {
          system: name,
          message_id: job.job_id,
          destination: resque_job.fetch("queue", job.queue_name),
          body_size: body_size(resque_job.fetch("payload") { wrapper_payload(job_data) }),
          receive_latency: Sentry::Utils::Latency.milliseconds_since(job_data&.[]("enqueued_at"))
        }.compact
      end

      def span_origin(job:)
        SPAN_ORIGIN
      end

      def integration(job:)
        Sentry::Resque
      end

      def report_retried_exception?(job:, exception:)
        false
      end

      private

      def active_job_data(job)
        job._sentry_job_data if job.respond_to?(:_sentry_job_data)
      end

      def handed_over_resque_job(job_data)
        resque_job = job_data[RESQUE_JOB_KEY] if job_data.is_a?(Hash)
        resque_job.is_a?(Hash) ? resque_job : {}
      end

      def wrapper_payload(job_data)
        { "class" => ACTIVE_JOB_WRAPPER, "args" => [job_data] } if job_data
      end

      def body_size(payload)
        ::Resque.encode(payload).bytesize if payload
      rescue StandardError
        nil
      end
    end

    Sentry.register_job_extension(ActiveJobExtension.new)
  end
end
