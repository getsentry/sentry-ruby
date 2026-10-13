# frozen_string_literal: true

require "sentry/sidekiq/context_filter"
require "sentry/sidekiq/failure_reporting"

module Sentry
  module Sidekiq
    class ErrorHandler
      def initialize(failure_reporting: FailureReporting.new)
        @failure_reporting = failure_reporting
      end

      # @param ex [Exception] the exception / error that occured
      # @param context [Hash or Array] Sidekiq error context
      # @param sidekiq_config [Sidekiq::Config, Hash] Sidekiq configuration,
      #   Defaults to nil.
      #   Sidekiq will pass the config in starting Sidekiq 7.1.5, see
      #   https://github.com/sidekiq/sidekiq/pull/6051
      def call(ex, context, sidekiq_config = nil)
        return unless Sentry.initialized?

        scope = Sentry.get_current_scope
        scope.set_transaction_name(ContextFilter.new(context).transaction_name, source: :task) unless scope.transaction_name

        job = context[:job]
        return unless @failure_reporting.report?(job, sidekiq_config)

        Sentry::Sidekiq.capture_exception(
          ex,
          hint: { background: false },
          contexts: { sidekiq: ContextFilter.new(context).filtered }
        )
      ensure
        scope&.clear
      end
    end
  end
end
