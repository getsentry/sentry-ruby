# frozen_string_literal: true
require 'logger'

module Raven
  class Logger
    LOG_PREFIX = "** [Raven] ".freeze

    [
      :fatal,
      :error,
      :warn,
      :info,
      :debug
    ].each do |level|
      define_method level do |*args, &block|
        logger = Raven.configuration[:logger]
        logger = ::Logger.new(STDOUT) if logger.nil?
        return unless logger

        msg = args[0] # Block-level default args is a 1.9 feature
        msg ||= block.call if block

        logger.send(level, "sentry") { "#{LOG_PREFIX}#{msg}" }
      end
    end
  end
end
