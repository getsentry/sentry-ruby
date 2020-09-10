module Raven
  class CLI
    def self.test(dsn = nil, silent = false, config = nil)
      config ||= Raven.configuration

      config.logger = if silent
                        ::Logger.new(nil)
                      else
                        logger = ::Logger.new(STDOUT)
                        logger.formatter = proc do |_severity, _datetime, _progname, msg|
                          "-> #{msg}\n"
                        end
                        logger
                      end

      config.timeout = 5
      config.dsn = dsn if dsn

      # wipe out env settings to ensure we send the event
      unless config.capture_allowed?
        env_name = config.environments.last || 'production'
        config.current_environment = env_name
      end

      instance = Raven::Instance.new(nil, config)

      instance.logger.debug "Sending a test event:"
      instance.logger.debug ""

      begin
        1 / 0
      rescue ZeroDivisionError => e
        evt = instance.capture_exception(e)
      end

      if evt
        instance.logger.debug "-> event ID: #{evt.id}"
        instance.logger.debug ""
        instance.logger.debug "Done!"
        evt
      else
        instance.logger.debug ""
        instance.logger.debug "An error occurred while attempting to send the event."
        false
      end
    end
  end
end
