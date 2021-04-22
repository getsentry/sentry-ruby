require "sentry/rails/active_job_context_filter"

module Sentry
  module Sidekiq
    class ContextFilter < Sentry::Rails::ActiveJobContextFilter
      SIDEKIQ_NAME = "Sidekiq".freeze

      def transaction_name_prefix
        SIDEKIQ_NAME
      end
    end
  end
end
