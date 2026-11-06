# frozen_string_literal: true

module Sentry
  module Resque
    # Support for ActiveJob jobs run through Resque, which reports them in one of
    # two modes:
    #
    # - By default, sentry-rails skips the Resque adapter and sentry-resque
    #   reports ActiveJob jobs like other Resque jobs.
    # - When the app removes the Resque adapter from
    #   `config.rails.skippable_job_adapters`, sentry-rails reports them through
    #   {Sentry::Resque::ActiveJobExtension}, and {ActiveJobSupport::Reporter}
    #   keeps sentry-resque from reporting them a second time.
    module ActiveJobSupport
      ACTIVE_JOB_ADAPTER = "ActiveJob::QueueAdapters::ResqueAdapter"
      ACTIVE_JOB_WRAPPER = "ActiveJob::QueueAdapters::ResqueAdapter::JobWrapper"

      # Returns whether the Resque payload wraps an ActiveJob job.
      #
      # @param payload [Hash]
      # @return [Boolean]
      def self.handles?(payload)
        payload.is_a?(Hash) && payload["class"] == ACTIVE_JOB_WRAPPER
      end

      # Prepended to {SentryReporter} when sentry-rails reports ActiveJob jobs on
      # Resque. For those jobs it only captures errors sentry-rails didn't, such as
      # ones raised before the job runs.
      module Reporter
        def record(queue, worker, payload, &block)
          return super unless ActiveJobSupport.handles?(payload)

          capture_unreported_exception(queue, worker, payload, &block)
        end

        private

        def capture_unreported_exception(queue, worker, payload)
          yield
        rescue Exception => exception # rubocop:disable Lint/RescueException
          unless Sentry.exception_captured?(exception)
            Sentry.with_scope do |scope|
              apply_job_scope(scope, queue, worker, payload)
              ::Sentry::Resque.capture_exception(exception, hint: { background: false })
            end
          end
          raise
        end
      end
    end
  end
end
