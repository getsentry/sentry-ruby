module Raven
  class CLI
    def self.test(dsn = nil, silent = false) # rubocop:disable all
      if silent
        Raven.configuration.logger = ::Logger.new(nil)
      else
        logger = ::Logger.new(STDOUT)
        logger.level = ::Logger::ERROR
        logger.formatter = proc do |_severity, _datetime, _progname, msg|
          "-> #{msg}\n"
        end

        Raven.configuration.logger = logger
      end

      Raven.configuration.timeout = 5
      Raven.configuration.dsn = dsn if dsn

      # wipe out env settings to ensure we send the event
      unless Raven.configuration.capture_allowed?
        env_name = Raven.configuration.environments.pop || 'production'
        Raven.logger.debug "Setting environment to #{env_name}"
        Raven.configuration.current_environment = env_name
      end

      Raven.logger.debug "Sending a test event:"
      Raven.logger.debug ""

      begin
        1 / 0
      rescue ZeroDivisionError => exception
        evt = Raven.capture_exception(exception)
      end

      if evt && !(evt.is_a? Thread)
        if evt.is_a? Hash
          Raven.logger.debug "-> event ID: #{evt[:event_id]}"
        else
          Raven.logger.debug "-> event ID: #{evt.id}"
        end
      elsif evt # async configuration
        if evt.value.is_a? Hash
          Raven.logger.debug "-> event ID: #{evt.value[:event_id]}"
        else
          Raven.logger.debug "-> event ID: #{evt.value.id}"
        end
      else
        Raven.logger.debug ""
        Raven.logger.debug "An error occurred while attempting to send the event."
        exit 1
      end

      Raven.logger.debug ""
      Raven.logger.debug "Done!"
      true
    end
  end
end
