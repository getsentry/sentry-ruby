module Raven
  class CLI
    def self.test(dsn = nil, silent = false, config = nil) # rubocop:disable all
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
        env_name = config.environments.pop || 'production'
        config.current_environment = env_name
      end

      instance = Raven::Instance.new(nil, config)

      instance.logger.debug "Sending a test event:"
      instance.logger.debug ""

      begin
        1 / 0
      rescue ZeroDivisionError => exception
        evt = instance.capture_exception(exception)
      end

      if evt && !(evt.is_a? Thread)
        if evt.is_a? Hash
          instance.logger.debug "-> event ID: #{evt[:event_id]}"
        else
          instance.logger.debug "-> event ID: #{evt.id}"
        end
      elsif evt # async configuration
        if evt.value.is_a? Hash
          instance.logger.debug "-> event ID: #{evt.value[:event_id]}"
        else
          instance.logger.debug "-> event ID: #{evt.value.id}"
        end
      else
        instance.logger.debug ""
        instance.logger.debug "An error occurred while attempting to send the event."
        exit 1
      end

      instance.logger.debug ""
      instance.logger.debug "Done!"
      evt
    end
  end
end
