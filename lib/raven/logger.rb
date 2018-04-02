# frozen_string_literal: true
require 'logger'

module Raven
  module Logger
    LOG_PREFIX = "** [Raven] ".freeze
    PROGNAME   = "sentry".freeze

    module Formatter
      def call(severity, timestamp, _progname, msg)
        super(severity, timestamp, PROGNAME, "#{LOG_PREFIX}#{msg}")
      end
    end

    def self.new(logger)
      logger = logger.dup
      original_formatter = logger.formatter || ::Logger::Formatter.new
      logger.formatter = proc { |severity, datetime, _progname, msg|
        original_formatter.call(severity, datetime, PROGNAME, "#{LOG_PREFIX}#{msg}")
      }
      logger
    end
  end
end
