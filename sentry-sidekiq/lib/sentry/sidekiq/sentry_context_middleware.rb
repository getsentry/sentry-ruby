require 'sentry/sidekiq/context_filter'

module Sentry
  module Sidekiq
    class SentryContextMiddleware
      def call(_worker, job, queue)
        return yield unless Sentry.initialized?

        context_filter = Sentry::Sidekiq::ContextFilter.new(job)

        Sentry.clone_hub_to_current_thread
        scope = Sentry.get_current_scope
        scope.set_extras(sidekiq: job.merge("queue" => queue))
        scope.set_transaction_name(context_filter.transaction_name)

        yield

        # don't need to use ensure here
        # if the job failed, we need to keep the scope for error handler. and the scope will be cleared there
        scope.clear
      end
    end
  end
end
