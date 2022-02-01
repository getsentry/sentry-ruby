module Sentry
  module Rails
    module ActiveJobExtensions
      def perform_now
        Adapter.new(self).perform { super }
      end

      class Adapter
        attr_reader :job

        def initialize(job)
          @job = job
        end

        def perform
          if !Sentry.initialized? || already_supported_by_sentry_integration?
            yield
          else
            Sentry.with_scope do |scope|
              capture_and_reraise_with_sentry(scope) { yield }
            end
          end
        end

        def capture_and_reraise_with_sentry(scope, &block)
          scope.set_transaction_name(job.class.name)
          transaction =
            if job.is_a?(::Sentry::SendEventJob)
              nil
            else
              Sentry.start_transaction(name: scope.transaction_name, op: "active_job")
            end

          scope.set_span(transaction) if transaction

          return_value = block.call

          finish_sentry_transaction(transaction, 200)

          return_value
        rescue Exception => e # rubocop:disable Lint/RescueException
          finish_sentry_transaction(transaction, 500)

          Sentry::Rails.capture_exception(
            e,
            extra: sentry_context,
            tags: {
              job_id: job.job_id,
              provider_job_id: job.provider_job_id
            }
          )
          raise e
        end

        def finish_sentry_transaction(transaction, status)
          return unless transaction

          transaction.set_http_status(status)
          transaction.finish
        end

        def already_supported_by_sentry_integration?
          Sentry.configuration.rails.skippable_job_adapters.include?(job.class.queue_adapter.class.to_s)
        end

        def sentry_context
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
