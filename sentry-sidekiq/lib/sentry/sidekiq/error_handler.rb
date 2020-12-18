require 'sentry/sidekiq/context_filter'

module Sentry
  module Sidekiq
    class ErrorHandler
      SIDEKIQ_NAME = "Sidekiq".freeze

      def call(ex, context)
        return unless Sentry.initialized?
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

      # this will change in the future:
      # https://github.com/mperham/sidekiq/pull/3161
      def transaction_from_context(context)
        classname = (context["wrapped"] || context["class"] ||
                      (context[:job] && (context[:job]["wrapped"] || context[:job]["class"]))
                    )
        if classname
          "#{SIDEKIQ_NAME}/#{classname}"
        elsif context[:event]
          "#{SIDEKIQ_NAME}/#{context[:event]}"
        else
          SIDEKIQ_NAME
        end
      end
    end
  end
end
