# frozen_string_literal: true

require "logger"

module Sentry
  class Logger < ::Logger
    LOG_PREFIX = "** [Sentry] "
    PROGNAME   = "sentry"

    # https://develop.sentry.dev/sdk/telemetry/logs/#log-severity-number
    LEVELS = {
      "trace" => 1,
      "debug" => 5,
      "info" => 9,
      "warn" => 13,
      "error" => 17,
      "fatal" => 21
    }.freeze

    def initialize(*)
      super
      @level = ::Logger::INFO
      original_formatter = ::Logger::Formatter.new
      @default_formatter = proc do |severity, datetime, _progname, msg|
        msg = "#{LOG_PREFIX}#{msg}"
        original_formatter.call(severity, datetime, PROGNAME, msg)
      end
    end
  end
end
