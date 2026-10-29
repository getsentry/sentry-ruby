# frozen_string_literal: true

require "sentry/rails/active_job_extension"
require "sentry/sidekiq/active_job_support/handoff"

module Sentry
  module Sidekiq
    class ActiveJobExtension < Sentry::Rails::ActiveJobExtension
      include ActiveJobSupport::Handoff

      def initialize
        super(name: "sidekiq_active_job")
        @backend = Sentry::Sidekiq.job_extension
      end

      def handles?(job)
        handles_active_job?(job)
      end

      def scope_data(job:)
        sidekiq_job = handed_over_sidekiq_job(job)
        sidekiq_job ? @backend.scope_data(job: sidekiq_job) : super
      end

      def messaging_data(job:)
        sidekiq_job = handed_over_sidekiq_job(job)
        sidekiq_job ? @backend.consumer_messaging_data(sidekiq_job) : super
      end

      def retry_info(job:)
        sidekiq_job = handed_over_sidekiq_job(job)
        sidekiq_job ? @backend.retry_info(job: sidekiq_job) : super
      end

      def extract_trace_headers(job:, payload:)
        sidekiq_job = sidekiq_job_in(payload)
        sidekiq_job ? @backend.extract_trace_headers(job: job, payload: sidekiq_job) : super
      end

      def transaction_name(job:)
        "#{JobExtension::SIDEKIQ_NAME}/#{super}"
      end

      def span_origin(job:)
        JobExtension::SPAN_ORIGIN
      end

      def integration(job:)
        Sentry::Sidekiq
      end

      def report_retried_exception?(job:, exception:)
        false
      end

      def producer(job:)
        @backend.producer(job: job)
      end

      private

      def handed_over_sidekiq_job(job)
        sidekiq_job_in(job._sentry_job_data) if job.respond_to?(:_sentry_job_data)
      end
    end

    Sentry.register_job_extension(ActiveJobExtension.new)
  end
end
