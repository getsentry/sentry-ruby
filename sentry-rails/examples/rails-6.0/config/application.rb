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

    config.webpacker.check_yarn_integrity = false
    config.active_job.queue_adapter = :sidekiq
  end
end
