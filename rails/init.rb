require 'raven'

begin
  Raven.logger.info("Loading Raven #{Raven::VERSION} for #{Rails::VERSION::STRING}")      
  Rails.configuration.middleware.use "Raven::Rack"
rescue => e
  STDERR.puts "There was a problem configuring Raven: #{e.message}"
  Raven.logger.error(e.message)
  Raven.logger.error(e.backtrace)
end
