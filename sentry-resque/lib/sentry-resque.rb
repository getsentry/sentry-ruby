# frozen_string_literal: true

require "resque"
require "sentry-ruby"
require "sentry/integrable"
require "sentry/resque/configuration"
require "sentry/resque/version"
require "sentry/resque"

module Sentry
  module Resque
    extend Sentry::Integrable

    register_integration name: "resque", version: Sentry::Resque::VERSION

    if defined?(::Rails::Railtie)
      class Railtie < ::Rails::Railtie
        config.after_initialize do
          next unless Sentry.initialized? && defined?(::Sentry::Rails)

          Sentry.configuration.rails.skippable_job_adapters << "ActiveJob::QueueAdapters::ResqueAdapter"
        end
      end
    end
  end
end
