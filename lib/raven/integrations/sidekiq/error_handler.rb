require 'raven/integrations/sidekiq/context_filter'

module Raven
  module Sidekiq
    class ErrorHandler
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
          "Sidekiq/#{classname}"
        elsif context[:event]
          "Sidekiq/#{context[:event]}"
        else
          "Sidekiq"
        end
      end
    end
  end
end
