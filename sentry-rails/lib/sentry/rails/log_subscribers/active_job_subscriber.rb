# frozen_string_literal: true

require "sentry/rails/log_subscriber"
require "sentry/rails/log_subscribers/parameter_filter"

module Sentry
  module Rails
    module LogSubscribers
      # LogSubscriber for ActiveJob events that captures background job execution
      # and logs them using Sentry's structured logging system.
      #
      # This subscriber captures various ActiveJob events including job execution,
      # enqueueing, retries, and failures with relevant job information.
      #
      # @example Usage
      #   # Enable structured logging for ActiveJob
      #   Sentry.init do |config|
      #     config.enable_logs = true
      #     config.rails.structured_logging = true
      #     config.rails.structured_logging.subscribers = { active_job: Sentry::Rails::LogSubscribers::ActiveJobSubscriber }
      #   end
      class ActiveJobSubscriber < Sentry::Rails::LogSubscriber
        include ParameterFilter

        # Handle perform.active_job events
        #
        # @param event [ActiveSupport::Notifications::Event] The job performance event
        def perform(event)
          job = event.payload[:job]
          duration = duration_ms(event)

          attributes = {
            job_class: job.class.name,
            job_id: job.job_id,
            queue_name: job.queue_name,
            duration_ms: duration,
            executions: job.executions,
            priority: job.priority
          }

          attributes[:adapter] = job.class.queue_adapter.class.name

          if job.scheduled_at
            attributes[:scheduled_at] = job.scheduled_at.iso8601
            attributes[:delay_ms] = ((Time.current - job.scheduled_at) * 1000).round(2)
          end

          if Sentry.configuration.send_default_pii && job.arguments.present?
            filtered_args = filter_sensitive_arguments(job.arguments)
            attributes[:arguments] = filtered_args unless filtered_args.empty?
          end

          message = "Job performed: #{job.class.name}"

          log_structured_event(
            message: message,
            level: :info,
            attributes: attributes
          )
        end

        # Handle enqueue.active_job events
        #
        # @param event [ActiveSupport::Notifications::Event] The job enqueue event
        def enqueue(event)
          job = event.payload[:job]

          attributes = {
            job_class: job.class.name,
            job_id: job.job_id,
            queue_name: job.queue_name,
            priority: job.priority
          }

          attributes[:adapter] = job.class.queue_adapter.class.name if job.class.respond_to?(:queue_adapter)

          if job.scheduled_at
            attributes[:scheduled_at] = job.scheduled_at.iso8601
            attributes[:delay_seconds] = (job.scheduled_at - Time.current).round(2)
          end

          message = "Job enqueued: #{job.class.name}"

          log_structured_event(
            message: message,
            level: :info,
            attributes: attributes
          )
        end

        def retry_stopped(event)
          job = event.payload[:job]
          error = event.payload[:error]

          attributes = {
            job_class: job.class.name,
            job_id: job.job_id,
            queue_name: job.queue_name,
            executions: job.executions,
            error_class: error.class.name,
            error_message: error.message
          }

          message = "Job retry stopped: #{job.class.name}"

          log_structured_event(
            message: message,
            level: :error,
            attributes: attributes
          )
        end

        def discard(event)
          job = event.payload[:job]
          error = event.payload[:error]

          attributes = {
            job_class: job.class.name,
            job_id: job.job_id,
            queue_name: job.queue_name,
            executions: job.executions
          }

          attributes[:error_class] = error.class.name if error
          attributes[:error_message] = error.message if error

          message = "Job discarded: #{job.class.name}"

          log_structured_event(
            message: message,
            level: :warn,
            attributes: attributes
          )
        end

        private

        def filter_sensitive_arguments(arguments)
          return [] unless arguments.is_a?(Array)

          arguments.map do |arg|
            case arg
            when Hash
              filter_sensitive_params(arg)
            when String
              arg.length > 100 ? "[FILTERED: #{arg.length} chars]" : arg
            else
              arg
            end
          end
        end
      end
    end
  end
end
