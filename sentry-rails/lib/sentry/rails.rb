require "sentry-ruby"
require "sentry/rails/configuration"
require "sentry/rails/railtie"
require "sentry/rails/tracing"

module Sentry
  module Rails
    META = { "name" => "sentry.ruby.rails", "version" => Sentry::Rails::VERSION }.freeze
  end

  def self.sdk_meta
    Sentry::Rails::META
  end
end
