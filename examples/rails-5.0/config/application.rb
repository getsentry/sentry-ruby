require_relative 'boot'

require 'rails/all'

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module Rails50
  class Application < Rails::Application
    config.consider_all_requests_local = false

    config.rails_activesupport_breadcrumbs = true

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
