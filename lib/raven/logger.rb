# frozen_string_literal: true
require 'logger'

module Raven
  class Logger
    LOG_PREFIX = "** [Raven] ".freeze

    LEVELS = {
      :debug => ::Logger::DEBUG,
      :info => ::Logger::INFO,
      :warn => ::Logger::WARN,
      :error => ::Logger::ERROR,
      :fatal => ::Logger::FATAL
    }.freeze

    [
      :fatal,
      :error,
      :warn,
      :info,
      :debug,
    ].each do |level|
      define_method level do |*args, &block|
        msg = args[0] # Block-level default args is a 1.9 feature
        msg ||= block.call if block
        logger = Raven.configuration[:logger]
        logger = ::Logger.new(STDOUT) if logger.nil?

        logger.add(LEVELS[level], "#{LOG_PREFIX}#{msg}", "sentry") if logger
      end
    end
  end
end
