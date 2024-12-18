# frozen_string_literal: true

require "sentry/rails/active_job/configuration"
module Sentry
  module Rails
    module ActiveJobExtensions
      def perform_now
        if !Sentry.initialized? || already_supported_by_sentry_integration?
          super
        else
          SentryReporter.record(self) do
            super
          end
        end
      end

      def already_supported_by_sentry_integration?
        Sentry.configuration.rails.skippable_job_adapters.include?(self.class.queue_adapter.class.to_s)
      end

      class SentryReporter
        OP_NAME = "queue.active_job"
        SPAN_ORIGIN = "auto.queue.active_job"

        class << self
          def record(job, &block)
            Sentry.with_scope do |scope|
              begin
                scope.set_transaction_name(job.class.name, source: :task)
                transaction =
                  if job.is_a?(::Sentry::SendEventJob)
                    nil
                  else
                    Sentry.start_transaction(
                      name: scope.transaction_name,
                      source: scope.transaction_source,
                      op: OP_NAME,
                      origin: SPAN_ORIGIN
                    )
                  end

                scope.set_span(transaction) if transaction

                yield.tap do
                  finish_sentry_transaction(transaction, 200)
                end
              rescue Exception => e # rubocop:disable Lint/RescueException
                finish_sentry_transaction(transaction, 500)

                unless Sentry.configuration.active_job.report_after_job_retries
                  capture_exception(job, e)
                end

                raise
              end
            end
          end

          def capture_exception(job, e)
            Sentry::Rails.capture_exception(
              e,
              extra: sentry_context(job),
              tags: {
                job_id: job.job_id,
                provider_job_id: job.provider_job_id
              }
            )
          end

          def register_retry_stopped_subscriber
            ActiveSupport::Notifications.subscribe("retry_stopped.active_job") do |*args|
              retry_stopped_handler(*args)
            end
          end

          def retry_stopped_handler(*args)
            return unless Sentry.configuration.active_job.report_after_job_retries

            event = ActiveSupport::Notifications::Event.new(*args)
            job = event.payload[:job]
            error = event.payload[:error]
            capture_exception(job, error)
          end

          def finish_sentry_transaction(transaction, status)
            return unless transaction

            transaction.set_http_status(status)
            transaction.finish
          end

          def sentry_context(job)
            {
              active_job: job.class.name,
              arguments: sentry_serialize_arguments(job.arguments),
              scheduled_at: job.scheduled_at,
              job_id: job.job_id,
              provider_job_id: job.provider_job_id,
              locale: job.locale
            }
          end

          def sentry_serialize_arguments(argument)
            case argument
            when Range
              if (argument.begin || argument.end).is_a?(ActiveSupport::TimeWithZone)
                argument.to_s
              else
                argument.map { |v| sentry_serialize_arguments(v) }
              end
            when Hash
              argument.transform_values { |v| sentry_serialize_arguments(v) }
            when Array, Enumerable
              argument.map { |v| sentry_serialize_arguments(v) }
            when ->(v) { v.respond_to?(:to_global_id) }
              argument.to_global_id.to_s rescue argument
            else
              argument
            end
          end
        end
      end
    end
  end
end
