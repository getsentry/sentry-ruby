# frozen_string_literal: true

require "good_job"
require "sentry-ruby"
require "sentry/integrable"
require "sentry/good_job/version"
require "sentry/good_job/configuration"
require "sentry/good_job/context_helpers"
require "sentry/good_job/active_job_extensions"
require "sentry/good_job/cron_helpers"

module Sentry
  module GoodJob
    extend Sentry::Integrable

    register_integration name: "good_job", version: Sentry::GoodJob::VERSION

    if defined?(::Rails::Railtie)
      class Railtie < ::Rails::Railtie
        config.after_initialize do
          next unless Sentry.initialized? && defined?(::Sentry::Rails)

          # Automatic setup for Good Job when the integration is enabled
          if Sentry.configuration.enabled_patches.include?(:good_job)
            Sentry::GoodJob.setup_good_job_integration
          end
        end
      end
    end

    def self.setup_good_job_integration
      # Enhance sentry-rails ActiveJob integration with GoodJob-specific context
      Sentry::GoodJob::ActiveJobExtensions.setup

      # Set up cron monitoring for all scheduled jobs (automatically configured from Good Job config)
      if Sentry.configuration.good_job.enable_cron_monitors
        Sentry::GoodJob::CronHelpers::Integration.setup_monitoring_for_scheduled_jobs
      end

      Sentry.configuration.sdk_logger.info "Sentry Good Job integration initialized automatically"
    end

    # Delegate capture_exception so internal components can be tested in isolation
    def self.capture_exception(exception, **options)
      ::Sentry.capture_exception(exception, **options)
    end
  end
end
