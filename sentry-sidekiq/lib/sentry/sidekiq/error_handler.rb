# frozen_string_literal: true

require "sentry/sidekiq/context_filter"
require "sentry/sidekiq/sentry_context_middleware"

module Sentry
  module Sidekiq
    class ErrorHandler
      WITH_SIDEKIQ_7 = ::Gem::Version.new(::Sidekiq::VERSION) >= ::Gem::Version.new("7.0")

      def initialize(extension = Sentry::Sidekiq.job_extension)
        @extension = extension
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
        extension = Sentry::Sidekiq.job_extension_for(job, default: @extension)
        return unless extension.report_exception?(job: job, exception: ex, sidekiq_config: sidekiq_config)

        extension.capture_exception(job: job, exception: ex, contexts: { sidekiq: extension.error_context(context) })
      ensure
        scope&.clear
      end
    end
  end
end
