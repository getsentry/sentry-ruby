# frozen_string_literal: true

require "resque"
require "sentry-ruby"
require "sentry/integrable"
require "sentry/resque/configuration"
require "sentry/resque/version"
require "sentry/resque"

module Sentry
  module Resque
    extend Sentry::Integrable

    register_integration name: "resque", version: Sentry::Resque::VERSION
  end
end

require "sentry/resque/railtie" if defined?(::Rails::Railtie)
