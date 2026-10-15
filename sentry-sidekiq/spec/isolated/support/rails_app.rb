# frozen_string_literal: true

begin
  require "simplecov"
  SimpleCov.command_name "SidekiqRails"
rescue LoadError
end

require "sentry-rails"

# This MUST be required after sentry-rails because it requires sentry-sidekiq
# which checks if Railtie is defined to properly set things up
require_relative "../../spec_helper"

# This is needed to prevent Sidekiq 6.5 crash
if SIDEKIQ_VERSION >= Gem::Version.new("6.5") && SIDEKIQ_VERSION < Gem::Version.new("7.0")
  # NoMethodError:
  #  undefined method 'broadcast' for class ActiveSupport::Logger
  #  /workspace/sentry/vendor/gems/3.4.5/gems/sidekiq-6.5.7/lib/sidekiq/rails.rb:46:in 'block (2 levels) in <class:Rails>'
  Rails.logger = Logger.new($stdout)
end

class TestApp < Rails::Application
end

BOOTED_APPS = []

def make_basic_app(&sentry_config)
  return reinitialize_basic_app(BOOTED_APPS.first, &sentry_config) if BOOTED_APPS.any?

  boot_basic_app(&sentry_config).tap { |app| BOOTED_APPS << app }
end

def reinitialize_basic_app(app, &sentry_config)
  perform_basic_setup(&sentry_config)
  ActiveSupport.run_load_hooks(:after_initialize, app)
  app
end

def boot_basic_app(&sentry_config)
  app = Class.new(TestApp) do
    def self.name
      "RailsTestApp"
    end
  end

  app.config.hosts = nil
  app.config.secret_key_base = "test"
  app.config.eager_load = false

  app.initializer :configure_sentry do
    perform_basic_setup(&sentry_config)
  end

  app.initialize!
  Rails.application = app
  app
end
