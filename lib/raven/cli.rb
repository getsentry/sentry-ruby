require 'raven'

module Raven
  class CLI
    def self.test(dsn=nil)
      require 'logger'

      logger = ::Logger.new(STDOUT)
      logger.level = ::Logger::ERROR
      logger.formatter = proc do |severity, datetime, progname, msg|
        "-> #{msg}\n"
      end

      Raven.configuration.logger = logger

      if dsn then
        Raven.configuration.dsn = dsn
      end

      # wipe out env settings to ensure we send the event
      if !Raven.configuration.send_in_current_environment? then
        environments = Raven.configuration.environments
        env_name = (environments && environments[0]) || 'production'
        puts "Setting environment to #{env_name}"
        Raven.configuration.current_environment = env_name
      end

      if !Raven.configuration.server then
        puts "Your client is not configured!"
        exit 1
      end

      puts "Client configuration:"
      ['server', 'project_id', 'public_key', 'secret_key'].each do |key|
        if !Raven.configuration[key] then
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

      if evt then
        puts "-> event ID: #{evt.id}"
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