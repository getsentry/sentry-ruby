module Sentry
  module Sidekiq
    class CleanupMiddleware
      def call(_worker, job, queue)
        return yield unless Sentry.initialized?

        Sentry.clone_hub_to_current_thread
        Sentry.with_scope do |scope|
          scope.set_extras(sidekiq: job.merge("queue" => queue))
          scope.set_transaction_name("Sidekiq/#{job["class"]}")

          begin
            yield
          rescue => ex
            Sentry.capture_exception(ex)
          end
        end
      end
    end
  end
end
