require 'time'
require 'sidekiq'
require 'raven/integrations/sidekiq/cleanup_middleware'
require 'raven/integrations/sidekiq/error_handler'

if Sidekiq::VERSION > '3'
  Sidekiq.configure_server do |config|
    config.error_handlers << Raven::Sidekiq::ErrorHandler.new
    config.server_middleware do |chain|
      chain.add Raven::Sidekiq::CleanupMiddleware
    end
  end
end
