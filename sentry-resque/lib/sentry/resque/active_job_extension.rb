# frozen_string_literal: true

require "sentry/rails/active_job_extension"
require "sentry/resque/active_job_support/reporter"

module Sentry
  module Resque
    # The extension sentry-rails uses for ActiveJob jobs on Resque when the app
    # lets sentry-rails report them. It keeps sentry-resque's context, tags,
    # origin and integration, so these jobs look the same in Sentry in either mode.
    #
    # @see ActiveJobSupport
    class ActiveJobExtension < Sentry::Rails::ActiveJobExtension
      SPAN_ORIGIN = "auto.queue.resque"
      MESSAGING_SYSTEM = "resque"

      def initialize(name: :resque, integration: Sentry::Resque, origin: SPAN_ORIGIN, **dependencies)
        super(name: name, integration: integration, origin: origin, **dependencies)
      end

      # Adds sentry-resque's `Active-Job` context and `resque.queue` tag.
      #
      # @see Sentry::JobExtensions::Extension#scope_data
      def scope_data(job:, **)
        job_data = job._sentry_job_data || {}
        context = {
          job_class: job.class.name,
          job_id: job.job_id,
          executions: job_data["executions"],
          exception_executions: job_data["exception_executions"],
          locale: job_data["locale"],
          enqueued_at: job_data["enqueued_at"],
          queue: job.queue_name
        }
        context[:arguments] = job_data["arguments"] if Sentry.configuration.data_collection.queues

        { contexts: { "Active-Job": context }, tags: { "resque.queue" => job.queue_name } }
      end

      # Describes the Resque message being processed.
      #
      # @see Sentry::JobExtensions::Extension#messaging_data
      def messaging_data(job:, **)
        job_data = job._sentry_job_data
        data = {
          system: MESSAGING_SYSTEM,
          message_id: job.job_id,
          destination: job.queue_name,
          retry_count: (job.executions.to_i if job.respond_to?(:executions)),
          receive_latency: Sentry::Utils::Latency.milliseconds_since(job_data&.[]("enqueued_at"))
        }
        data[:body_size] = body_size(job_data) if Sentry.get_current_scope.get_span&.sampled
        data.compact
      end

      private

      def body_size(job_data)
        ::Resque.encode("class" => ActiveJobSupport::ACTIVE_JOB_WRAPPER, "args" => [job_data]).bytesize if job_data
      rescue StandardError
        nil
      end
    end

    Sentry::Rails.register_active_job_extension(:resque, ActiveJobExtension.new)
  end
end
