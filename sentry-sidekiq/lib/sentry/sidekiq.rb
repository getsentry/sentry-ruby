require "sidekiq"
require "sentry-ruby"
require "sentry/sidekiq/error_handler"
require "sentry/sidekiq/cleanup_middleware"
# require "sentry/sidekiq/configuration"

module Sentry
  module Sidekiq
    META = { "name" => "sentry.ruby.sidekiq", "version" => Sentry::Sidekiq::VERSION }.freeze
  end

  def self.sdk_meta
    Sentry::Sidekiq::META
  end
end

Sidekiq.configure_server do |config|
  config.error_handlers << Sentry::Sidekiq::ErrorHandler.new
  config.server_middleware do |chain|
    chain.add Sentry::Sidekiq::CleanupMiddleware
  end
end

