module Raven
  class Logger
    LOG_PREFIX = "** [Raven] "

    [
      :fatal,
      :error,
      :warn,
      :info,
      :debug,
    ].each do |level|
      define_method level do |msg, &block|
        msg ||= block.call if block
        logger = Raven.configuration[:logger]
        logger.send(level, "#{LOG_PREFIX}#{msg}") if logger
      end
    end

  end
end
