# frozen_string_literal: true

require "action_cable/engine"
require "active_storage/engine"

require "sentry/rails/error_subscriber"

module Sentry
  class TestRailsApp < Sentry::Rails::Test::Application[:latest]
    def configure
      super
      config.active_storage.service = :test
      config.enable_reloading = false
    end

    def before_initialize!
      # Zeitwerk checks if registered loaders load paths repeatedly and raises error if that happens.
      # And because every new Rails::Application instance registers its own loader, we need to clear previously registered ones from Zeitwerk.
      Zeitwerk::Registry.loaders.clear

      # Rails removes the support of multiple instances, which includes freezing some setting values.
      ActiveSupport::Dependencies.autoload_once_paths = []
      ActiveSupport::Dependencies.autoload_paths = []

      # there are a few Rails initializers/finializers that register hook to the executor
      # because the callbacks are stored inside the `ActiveSupport::Executor` class instead of an instance
      # the callbacks duplicate after each time we initialize the application and cause issues when they're executed
      ActiveSupport::Executor.reset_callbacks(:run)
      ActiveSupport::Executor.reset_callbacks(:complete)

      # Rails uses this module to set a global context for its ErrorReporter feature.
      # this needs to be cleared so previously set context won't pollute later reportings (see ErrorSubscriber).
      ActiveSupport::ExecutionContext.clear

      ActionCable::Channel::Base.reset_callbacks(:subscribe)
      ActionCable::Channel::Base.reset_callbacks(:unsubscribe)

      # Rails 7.1 stores the error reporter directly under the ActiveSupport class.
      # So we need to make sure the subscriber is not subscribed unexpectedly before any tests
      ActiveSupport.error_reporter.unsubscribe(Sentry::Rails::ErrorSubscriber)

      super
    end
  end
end
