# frozen_string_literal: true

require "sentry/delayed_job/active_job_support/plugin"

module Sentry
  module DelayedJob
    # Sets up how ActiveJob jobs on delayed_job are reported in Rails apps.
    #
    # @see ActiveJobSupport
    class Railtie < ::Rails::Railtie
      initializer "sentry.delayed_job.skippable_job_adapter", before: :load_environment_config do
        next unless defined?(::Sentry::Rails)

        Sentry::Configuration.after(:initialize) { rails.skippable_job_adapters << ActiveJobSupport::ACTIVE_JOB_ADAPTER }
        # The callback only covers configurations created from here on, so an app that
        # initialized Sentry earlier gets the adapter added to its current configuration.
        Sentry.configuration.rails.skippable_job_adapters << ActiveJobSupport::ACTIVE_JOB_ADAPTER if Sentry.initialized?
      end

      config.after_initialize do
        next unless defined?(::Sentry::Rails) && Sentry::Rails.active_job_owns_adapter?(ActiveJobSupport::ACTIVE_JOB_ADAPTER)

        require "sentry/delayed_job/active_job_extension"
        Plugin.singleton_class.prepend(ActiveJobSupport::Plugin)
      end
    end
  end
end
