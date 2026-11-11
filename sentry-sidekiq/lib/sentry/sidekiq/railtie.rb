# frozen_string_literal: true

require "sentry/sidekiq/active_job_support/server_middleware"

module Sentry
  module Sidekiq
    # Sets up how ActiveJob jobs on Sidekiq are reported in Rails apps.
    #
    # @see ActiveJobSupport
    class Railtie < ::Rails::Railtie
      initializer "sentry.sidekiq.skippable_job_adapter", before: :load_environment_config do
        next unless defined?(::Sentry::Rails)

        Sentry::Configuration.after(:initialize) { rails.skippable_job_adapters << ActiveJobSupport::ACTIVE_JOB_ADAPTER }
        # The callback only covers configurations created from here on, so an app that
        # initialized Sentry earlier gets the adapter added to its current configuration.
        Sentry.configuration.rails.skippable_job_adapters << ActiveJobSupport::ACTIVE_JOB_ADAPTER if Sentry.initialized?
      end

      config.after_initialize do
        next unless defined?(::Sentry::Rails) && Sentry::Rails.active_job_owns_adapter?(ActiveJobSupport::ACTIVE_JOB_ADAPTER)

        require "sentry/sidekiq/active_job_extension"
        SentryContextServerMiddleware.prepend(ActiveJobSupport::ServerMiddleware)
      end
    end
  end
end
