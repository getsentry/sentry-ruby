require 'sentry/sidekiq/context_filter'

module Sentry
  module Sidekiq
    class EventErrorHandler
      SIDEKIQ_NAME = "Sidekiq".freeze

      def call(ex, context)
        return unless Sentry.initialized?
        # let CleanupMiddleware handle job failures
        return if job_name_from_context(context)
        context = Sentry::Sidekiq::ContextFilter.new.filter_context(context)

        Sentry.with_scope do |scope|
          scope.set_transaction_name transaction_from_context(context)
          Sentry.capture_exception(
            ex,
            extra: { sidekiq: context },
            hint: { background: false }
          )
        end
      end

      private

      def job_name_from_context(context)
        # this will change in the future:
        # https://github.com/mperham/sidekiq/pull/3161
        (context["wrapped"] || context["class"] ||
         (context[:job] && (context[:job]["wrapped"] || context[:job]["class"]))
        )
      end

      def transaction_from_context(context)
        if context[:event]
          "#{SIDEKIQ_NAME}/#{context[:event]}"
        else
          SIDEKIQ_NAME
        end
      end
    end
  end
end
