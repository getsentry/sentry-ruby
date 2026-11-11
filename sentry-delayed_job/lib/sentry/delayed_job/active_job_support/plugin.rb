# frozen_string_literal: true

module Sentry
  module DelayedJob
    # Support for ActiveJob jobs run through delayed_job, which reports them in
    # one of two modes:
    #
    # - By default, sentry-rails skips the delayed_job adapter and
    #   sentry-delayed_job reports ActiveJob jobs like other delayed_job jobs.
    # - When the app removes the delayed_job adapter from
    #   `config.rails.skippable_job_adapters`, sentry-rails reports them through
    #   {Sentry::DelayedJob::ActiveJobExtension}, and {ActiveJobSupport::Plugin}
    #   keeps sentry-delayed_job from reporting them a second time.
    module ActiveJobSupport
      ACTIVE_JOB_ADAPTER = "ActiveJob::QueueAdapters::DelayedJobAdapter"
      ACTIVE_JOB_WRAPPER = "ActiveJob::QueueAdapters::DelayedJobAdapter::JobWrapper"
      RECORD_ID_KEY = "delayed_job_id"

      # Returns the `Active-Job` context sentry-delayed_job reports for the job's
      # serialized data.
      #
      # @param job_data [Hash, nil]
      # @return [Hash]
      def self.active_job_context(job_data)
        context = (job_data || {}).reject { |key, _value| key == Sentry::Rails::ActiveJobExtensions::SENTRY_PAYLOAD_KEY }
        context = context.reject { |key, _value| key == "arguments" } unless Sentry.configuration.data_collection.queues
        context.transform_keys(&:to_sym)
      end

      # Returns whether the delayed_job record wraps an ActiveJob job.
      #
      # @param job [Delayed::Job]
      # @return [Boolean]
      def self.handles?(job)
        job.payload_object.class.name == ACTIVE_JOB_WRAPPER
      rescue ::Delayed::DeserializationError
        false
      end

      # Prepended to {Sentry::DelayedJob::Plugin} when sentry-rails reports
      # ActiveJob jobs on delayed_job. For those jobs it passes the record id on to
      # sentry-rails and only captures errors sentry-rails didn't, such as ones
      # raised before the job runs.
      module Plugin
        def record(job, *args, &block)
          return super unless Sentry.initialized? && ActiveJobSupport.handles?(job)

          hand_over_record_id(job)
          capture_unreported_exception(job) { block.call(job, *args) }
        end

        private

        def hand_over_record_id(job)
          job_data = job.payload_object.job_data
          sentry_data = (job_data[Sentry::Rails::ActiveJobExtensions::SENTRY_PAYLOAD_KEY] ||= {})
          sentry_data[RECORD_ID_KEY] = job.id.to_s
        end

        def capture_unreported_exception(job)
          yield
        rescue Exception => exception # rubocop:disable Lint/RescueException
          unless Sentry.exception_captured?(exception)
            Sentry.with_scope do |scope|
              contexts = generate_contexts(job)
              contexts[DelayedJob::Plugin::ACTIVE_JOB_CONTEXT_KEY]&.delete(Sentry::Rails::ActiveJobExtensions::SENTRY_PAYLOAD_KEY.to_sym)
              apply_job_scope(scope, job, contexts)
              capture_exception(exception, job)
            end
          end
          raise
        end
      end
    end
  end
end
