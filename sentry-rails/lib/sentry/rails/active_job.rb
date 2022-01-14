module Sentry
  module Rails
    module ActiveJobExtensions
      def perform_now
        if !Sentry.initialized? || already_supported_by_sentry_integration?
          super
        else
          Sentry.with_scope do |scope|
            capture_and_reraise_with_sentry(scope) do
              super
            end
          end
        end
      end

      def capture_and_reraise_with_sentry(scope, &block)
        scope.set_transaction_name(self.class.name)
        transaction =
          if is_a?(::Sentry::SendEventJob)
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
            job_id: job_id,
            provider_job_id: provider_job_id
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
        Sentry.configuration.rails.skippable_job_adapters.include?(self.class.queue_adapter.class.to_s)
      end

      def sentry_context
        {
          active_job: self.class.name,
          arguments: sentry_serialize_arguments(arguments),
          scheduled_at: scheduled_at,
          job_id: job_id,
          provider_job_id: provider_job_id,
          locale: locale
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
