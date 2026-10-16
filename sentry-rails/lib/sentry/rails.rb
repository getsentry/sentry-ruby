# frozen_string_literal: true

require "rails"
require "sentry-ruby"
require "sentry/integrable"
require "sentry/rails/tracing"
require "sentry/rails/configuration"
require "sentry/rails/structured_logging"
require "sentry/rails/engine"
require "sentry/rails/railtie"
require "sentry/rails/solid_queue_recurring"

module Sentry
  module Rails
    extend Integrable
    register_integration name: "rails", version: Sentry::Rails::VERSION
  end
end
