require_relative "logger"
require_relative "logging/device"
require_relative "logging/handler"

module Sentry
  module Logging
    def self.setup_logger(config)
      if config._experiments[:enable_logs]
        config.logger = Device.new(handlers: [config.logger, Handler.new(config)])
      end

      config.logger
    end
  end
end
