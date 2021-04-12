require 'sentry/sidekiq/context_filter'

module Sentry
  module Sidekiq
    class ErrorHandler
      def call(ex, context)
        return unless Sentry.initialized?

        context_filter = Sentry::Sidekiq::ContextFilter.new(context)

        scope = Sentry.get_current_scope
        scope.set_transaction_name(context_filter.transaction_name) unless scope.transaction_name

        Sentry::Sidekiq.capture_exception(
          ex,
          contexts: { sidekiq: context_filter.filtered },
          hint: { background: false }
        )
      end
    end
  end
end
