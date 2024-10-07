# frozen_string_literal: true

require "delayed_job"
require "sentry-ruby"
require "sentry/integrable"
require "sentry/delayed_job/configuration"
require "sentry/delayed_job/version"
require "sentry/delayed_job/plugin"

module Sentry
  module DelayedJob
    extend Sentry::Integrable

    register_integration name: "delayed_job", version: Sentry::DelayedJob::VERSION

    if defined?(::Rails::Railtie)
      class Railtie < ::Rails::Railtie
        config.after_initialize do
          next unless Sentry.initialized? && defined?(::Sentry::Rails)

          Sentry.configuration.rails.skippable_job_adapters << "ActiveJob::QueueAdapters::DelayedJobAdapter"
        end
      end
    end
  end
end
