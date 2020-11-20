require_relative 'boot'

require 'rails/all'

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module Rails60
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 6.0

    # Settings in config/environments/* take precedence over those specified here.
    # Application configuration can go into files in config/initializers
    # -- all .rb files in that directory are automatically loaded after loading
    # the framework and any gems in your application.
    config.consider_all_requests_local = false

    # https://github.com/getsentry/raven-ruby/issues/494
    config.exceptions_app = self.routes

    config.middleware.insert_after ActionDispatch::DebugExceptions, Sentry::Rack::CaptureException
    config.middleware.insert 0, Sentry::Rack::Tracing

    Sentry.init do |config|
      config.breadcrumbs_logger = [:sentry_logger]
      config.dsn = 'https://2fb45f003d054a7ea47feb45898f7649@o447951.ingest.sentry.io/5434472'
      # config.async = lambda { |event| SentryJob.perform_later(event) }
    end
  end
end
