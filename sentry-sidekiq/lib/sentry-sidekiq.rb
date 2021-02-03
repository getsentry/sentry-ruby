require "sidekiq"
require "sentry-ruby"
require "sentry/integrable"
require "sentry/sidekiq/version"
require "sentry/sidekiq/error_handler"
require "sentry/sidekiq/sentry_context_middleware"
# require "sentry/sidekiq/configuration"

module Sentry
  module Sidekiq
    extend Sentry::Integrable

    register_integration name: "sidekiq", version: Sentry::Sidekiq::VERSION
  end
end

Sidekiq.configure_server do |config|
  config.error_handlers << Sentry::Sidekiq::ErrorHandler.new
  config.server_middleware do |chain|
    chain.add Sentry::Sidekiq::SentryContextMiddleware
  end
end

