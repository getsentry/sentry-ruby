require 'sentry/sidekiq/context_filter'

module Sentry
  module Sidekiq
    class ErrorHandler
      WITH_SIDEKIQ_7 = ::Gem::Version.new(::Sidekiq::VERSION) >= ::Gem::Version.new("7.0")

      def call(ex, context)
        return unless Sentry.initialized?

        context_filter = Sentry::Sidekiq::ContextFilter.new(context)

        scope = Sentry.get_current_scope
        scope.set_transaction_name(context_filter.transaction_name, source: :task) unless scope.transaction_name

        if Sentry.configuration.sidekiq.report_after_job_retries && retryable?(context)
          retry_count = context.dig(:job, "retry_count")
          if retry_count.nil? || retry_count < retry_limit(context) - 1
            return
          end
        end

        Sentry::Sidekiq.capture_exception(
          ex,
          contexts: { sidekiq: context_filter.filtered },
          hint: { background: false }
        )
      end

      private

      def retryable?(context)
        retry_option = context.dig(:job, "retry")
        # when `retry` is not specified, it's default is `true` and it means 25 retries.
        retry_option == true || (retry_option.is_a?(Integer) && retry_option.positive?)
      end

      def retry_limit(context)
        limit = context.dig(:job, "retry")

        case limit
        when Integer
          limit
        when TrueClass
          max_retries =
            if WITH_SIDEKIQ_7
              ::Sidekiq.default_configuration[:max_retries]
            else
              ::Sidekiq.options[:max_retries]
            end
          max_retries || 25
        else
          0
        end
      end
    end
  end
end
