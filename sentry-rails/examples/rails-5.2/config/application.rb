require_relative 'boot'

require 'rails/all'

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module Rails50
  class Application < Rails::Application
    # https://github.com/getsentry/raven-ruby/issues/494
    config.exceptions_app = self.routes

    # With this enabled 'exceptions_app' isnt executed, so instead we
    # set ``config.consider_all_requests_local = false`` in development.
    # config.action_dispatch.show_exceptions = false
  end
end
