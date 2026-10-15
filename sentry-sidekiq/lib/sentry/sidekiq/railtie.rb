# frozen_string_literal: true

module Sentry
  module Sidekiq
    class Railtie < ::Rails::Railtie
      config.after_initialize do
        next unless Sentry.initialized? && defined?(::Sentry::Rails)

        Sentry.configuration.rails.skippable_job_adapters << ActiveJobSupport::JobExtension::ACTIVE_JOB_ADAPTER
      end
    end
  end
end
