# frozen_string_literal: true

require "yabeda"
require "sentry-ruby"
require "sentry/integrable"
require "sentry/yabeda/version"
require "sentry/yabeda/adapter"
require "sentry/yabeda/collector"
require "sentry/yabeda/configuration"

module Sentry
  module Yabeda
    extend Sentry::Integrable

    register_integration name: "yabeda", version: Sentry::Yabeda::VERSION

    class << self
      attr_accessor :collector
    end
  end
end

::Yabeda.register_adapter(:sentry, Sentry::Yabeda::Adapter.new)
