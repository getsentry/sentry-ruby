require File.expand_path('../boot', __FILE__)

require 'rails/all'

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module Rails42
  class Application < Rails::Application
    # Settings in config/environments/* take precedence over those specified here.
    # Application configuration should go into files in config/initializers
    # -- all .rb files in that directory are automatically loaded.

    # Set Time.zone default to the specified zone and make Active Record auto-convert to this zone.
    # Run "rake -D time" for a list of tasks for finding time zone names. Default is UTC.
    # config.time_zone = 'Central Time (US & Canada)'

    # The default locale is :en and all translations from config/locales/*.rb,yml are auto loaded.
    # config.i18n.load_path += Dir[Rails.root.join('my', 'locales', '*.{rb,yml}').to_s]
    # config.i18n.default_locale = :de

    # Do not swallow errors in after_commit/after_rollback callbacks.
    config.active_record.raise_in_transactional_callbacks = true

    config.consider_all_requests_local = false

    # https://github.com/getsentry/raven-ruby/issues/494
    config.exceptions_app = self.routes

    # With this enabled 'exceptions_app' isnt executed, so instead we
    # set ``config.consider_all_requests_local = false`` in development.
    # config.action_dispatch.show_exceptions = false

    # Inject Sentry logger breadcrumbs
    require 'raven/breadcrumbs/logger'

    Raven.configure do |config|
      config.dsn = 'https://6bca098db7ef423ab983e26e27255fe8:650b2fcf94f942fe9093f656b809a94e@app.getsentry.com/3825'
    end
  end
end
