# frozen_string_literal: true

require "delayed_job"
require "sentry-ruby"
require "sentry/integrable"
require "sentry/delayed_job/configuration"
require "sentry/delayed_job/version"
require "sentry/delayed_job/plugin"

module Sentry
  module DelayedJob
    extend Sentry::Integrable

    register_integration name: "delayed_job", version: Sentry::DelayedJob::VERSION
  end
end

require "sentry/delayed_job/railtie" if defined?(::Rails::Railtie)
