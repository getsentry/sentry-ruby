require 'raven'

module Raven
  class CLI
    def self.test(dsn = nil)
      require 'logger'

      logger = ::Logger.new(STDOUT)
      logger.level = ::Logger::ERROR
      logger.formatter = proc do |_severity, _datetime, _progname, msg|
        "-> #{msg}\n"
      end

      Raven.configuration.logger = logger
      Raven.configuration.timeout = 5
      Raven.configuration.dsn = dsn if dsn

      # wipe out env settings to ensure we send the event
      unless Raven.configuration.send_in_current_environment?
        environments = Raven.configuration.environments
        env_name = (environments && environments[0]) || 'production'
        puts "Setting environment to #{env_name}"
        Raven.configuration.current_environment = env_name
      end

      unless Raven.configuration.server
        puts "Your client is not configured!"
        exit 1
      end

      puts "Client configuration:"
      ['server', 'project_id', 'public_key', 'secret_key'].each do |key|
        unless Raven.configuration[key]
          puts "Missing configuration for #{key}"
          exit 1
        end
        puts "-> #{key}: #{Raven.configuration[key]}"
      end
      puts ""

      puts "Sending a test event:"

      begin
        1 / 0
      rescue ZeroDivisionError => exception
        evt = Raven.capture_exception(exception)
      end

      if evt && !(evt.is_a? Thread)
        if evt.is_a? Hash
          puts "-> event ID: #{evt[:event_id]}"
        else
          puts "-> event ID: #{evt.id}"
        end
      elsif evt #async configuration
        puts "-> event ID: #{evt.value.id}"
      else
        puts ""
        puts "An error occurred while attempting to send the event."
        exit 1
      end

      puts ""
      puts "Done!"
    end
  end
end
