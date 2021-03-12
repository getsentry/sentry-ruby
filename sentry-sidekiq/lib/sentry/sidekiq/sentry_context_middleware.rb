require 'sentry/sidekiq/context_filter'

module Sentry
  module Sidekiq
    class SentryContextMiddleware
      def call(_worker, job, queue)
        return yield unless Sentry.initialized?

        context_filter = Sentry::Sidekiq::ContextFilter.new(job)

        Sentry.clone_hub_to_current_thread
        scope = Sentry.get_current_scope
        scope.set_tags(queue: queue, jid: job["jid"])
        scope.set_extras(sidekiq: job.merge("queue" => queue))
        scope.set_transaction_name(context_filter.transaction_name)
        transaction = Sentry.start_transaction(name: scope.transaction_name, op: "sidekiq")
        scope.set_span(transaction) if transaction

        begin
          yield
        rescue => e
          finish_transaction(transaction, 500)
          raise
        end

        finish_transaction(transaction, 200)
        # don't need to use ensure here
        # if the job failed, we need to keep the scope for error handler. and the scope will be cleared there
        scope.clear
      end

      def finish_transaction(transaction, status)
        return unless transaction

        transaction.set_http_status(status)
        transaction.finish
      end
    end
  end
end
