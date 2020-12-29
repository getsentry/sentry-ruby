module Sentry
  module Sidekiq
    class SentryContextMiddleware
      def call(_worker, job, queue)
        return yield unless Sentry.initialized?

        Sentry.clone_hub_to_current_thread
        scope = Sentry.get_current_scope
        scope.set_extras(sidekiq: job.merge("queue" => queue))
        scope.set_transaction_name("Sidekiq/#{job["class"]}")

        yield

        # don't need to use ensure here
        # if the job failed, we need to keep the scope for error handler. and the scope will be cleared there
        scope.clear
      end
    end
  end
end
