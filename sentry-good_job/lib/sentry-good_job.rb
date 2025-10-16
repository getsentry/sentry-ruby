# frozen_string_literal: true

require "good_job"
require "sentry-ruby"
require "sentry/integrable"
require "sentry/good_job/version"
require "sentry/good_job/configuration"
require "sentry/good_job/error_handler"
require "sentry/good_job/logger"
require "sentry/good_job/job_monitor"
require "sentry/good_job/cron_monitoring"

module Sentry
  module GoodJob
    extend Sentry::Integrable

    register_integration name: "good_job", version: Sentry::GoodJob::VERSION

    if defined?(::Rails::Railtie)
      class Railtie < ::Rails::Railtie
        config.after_initialize do
          next unless Sentry.initialized? && defined?(::Sentry::Rails)

          # Skip ActiveJob error reporting when using Good Job as the backend
          # since we handle it ourselves
          Sentry.configuration.rails.skippable_job_adapters << "ActiveJob::QueueAdapters::GoodJobAdapter"

          # Automatic setup for Good Job when the integration is enabled
          if Sentry.configuration.enabled_patches.include?(:good_job)
            Sentry::GoodJob.setup_good_job_integration
          end
        end
      end
    end

    def self.setup_good_job_integration
      # Sentry Rails integration already handles ActiveJob exceptions automatically
      # No need for custom error handling

      # Set up unified job monitoring for ApplicationJob
      Sentry::GoodJob::JobMonitor.setup_for_job_class(ApplicationJob)

      # Set up cron monitoring for all scheduled jobs (automatically configured from Good Job config)
      if Sentry.configuration.good_job.auto_setup_cron_monitoring
        Sentry::GoodJob::CronMonitoring::Integration.setup_monitoring_for_scheduled_jobs
      end

      Sentry::GoodJob::Logger.info "Sentry Good Job integration initialized automatically"
    end

    # Delegate capture_exception so internal components can be tested in isolation
    def self.capture_exception(exception, **options)
      ::Sentry.capture_exception(exception, **options)
    end
  end
end
