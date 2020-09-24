module Raven
  module Sidekiq
    class CleanupMiddleware
      def call(_worker, job, queue)
        Raven.context.transaction.push "Sidekiq/#{job['class']}"
        Raven.extra_context(:sidekiq => job.merge("queue" => queue))
        yield
        Context.clear!
        BreadcrumbBuffer.clear!
      end
    end
  end
end
