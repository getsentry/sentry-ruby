# frozen_string_literal: true

require "sidekiq"
require "sentry-ruby"
require "sentry/integrable"
require "sentry/sidekiq/version"
require "sentry/sidekiq/configuration"
require "sentry/sidekiq/job_extension"
require "sentry/sidekiq/error_handler"
require "sentry/sidekiq/sentry_context_middleware"

module Sentry
  module Sidekiq
    extend Sentry::Integrable

    register_integration name: "sidekiq", version: Sentry::Sidekiq::VERSION

    def self.job_extension
      @job_extension ||= JobExtension.new
    end

    Sentry.register_job_extension(job_extension)
  end
end

require "sentry/sidekiq/railtie" if defined?(::Rails::Railtie)

Sidekiq.configure_server do |config|
  config.error_handlers << Sentry::Sidekiq::ErrorHandler.new
  config.server_middleware do |chain|
    chain.add Sentry::Sidekiq::SentryContextServerMiddleware
  end
  config.client_middleware do |chain|
    chain.add Sentry::Sidekiq::SentryContextClientMiddleware
  end
end

Sidekiq.configure_client do |config|
  config.client_middleware do |chain|
    chain.add Sentry::Sidekiq::SentryContextClientMiddleware
  end
end

# patches
require "sentry/sidekiq/cron/helpers"
require "sentry/sidekiq/cron/job"
require "sentry/sidekiq-scheduler/scheduler"
