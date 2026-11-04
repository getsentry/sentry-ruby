# frozen_string_literal: true

require "sentry/resque/active_job_support/reporter"

module Sentry
  module Resque
    # Sets up how ActiveJob jobs on Resque are reported in Rails apps.
    #
    # @see ActiveJobSupport
    class Railtie < ::Rails::Railtie
      initializer "sentry.resque.skippable_job_adapter", before: :load_environment_config do
        next unless defined?(::Sentry::Rails)

        Sentry::Configuration.after(:initialize) { rails.skippable_job_adapters << ActiveJobSupport::ACTIVE_JOB_ADAPTER }
        Sentry.configuration.rails.skippable_job_adapters << ActiveJobSupport::ACTIVE_JOB_ADAPTER if Sentry.initialized?
      end

      config.after_initialize do
        next unless defined?(::Sentry::Rails) && Sentry::Rails.active_job_owns_adapter?(ActiveJobSupport::ACTIVE_JOB_ADAPTER)

        require "sentry/resque/active_job_extension"
        SentryReporter.singleton_class.prepend(ActiveJobSupport::Reporter)
      end
    end
  end
end
