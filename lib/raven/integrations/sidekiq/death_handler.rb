module Raven
  module Sidekiq
    class DeathHandler < ErrorHandler
      def call(job, ex)
        context = ContextFilter.filter_context(job)
        Raven.context.transaction.push transaction_from_context(context)
        Raven.capture_exception(
          ex,
          :message => ex.message,
          :extra => { :sidekiq => context }
        )
        Context.clear!
        BreadcrumbBuffer.clear!
      end
    end
  end
end
