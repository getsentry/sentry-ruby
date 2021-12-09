require 'sentry/sidekiq/context_filter'

module Sentry
  module Sidekiq
    class ErrorHandler
      def call(ex, context)
        return unless Sentry.initialized?

        context_filter = Sentry::Sidekiq::ContextFilter.new(context)

        scope = Sentry.get_current_scope
        scope.set_transaction_name(context_filter.transaction_name) unless scope.transaction_name

        retry_option = context.dig(:job, "retry")

        if Sentry.configuration.sidekiq.report_after_job_retries && retry_option.is_a?(Integer) && retry_option.positive?
          retry_count = context.dig(:job, "retry_count")
          if retry_count.nil? || retry_count < retry_option - 1
            return
          end
        end

        Sentry::Sidekiq.capture_exception(
          ex,
          contexts: { sidekiq: context_filter.filtered },
          hint: { background: false }
        )
      end
    end
  end
end
