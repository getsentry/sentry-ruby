module Sentry
  module Sidekiq
    class CleanupMiddleware
      def call(_worker, job, queue)
        return yield unless Sentry.initialized?

        Sentry.clone_hub_to_current_thread
        Sentry.with_scope do |scope|
          context = job.merge("queue" => queue)
          scope.set_extras(
            sidekiq: Sentry::Sidekiq::ContextFilter.new.filter_context(context)
          )
          scope.set_transaction_name("Sidekiq/#{job["class"]}")

          begin
            yield
          rescue => ex
            Sentry.capture_exception(ex, hint: { background: false })
            raise ex
          end
        end
      end
    end
  end
end
