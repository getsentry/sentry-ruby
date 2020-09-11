require 'raven/integrations/sidekiq/context_filter'

module Raven
  module Sidekiq
    class ErrorHandler
      SIDEKIQ_NAME = "Sidekiq".freeze

      def call(ex, context)
        context = ContextFilter.filter_context(context)
        Raven.context.transaction.push transaction_from_context(context)
        Raven.capture_exception(
          ex,
          :message => ex.message,
          :extra => { :sidekiq => context }
        )
        Context.clear!
        BreadcrumbBuffer.clear!
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
