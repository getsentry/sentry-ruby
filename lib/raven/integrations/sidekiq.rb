require 'time'
require 'sidekiq'
require 'raven/integrations/sidekiq/cleanup_middleware'
require 'raven/integrations/sidekiq/error_handler'
require 'raven/integrations/sidekiq/death_handler'

module Raven
  module Sidekiq
    def self.inject
      ::Sidekiq.configure_server do |config|
        if Raven.configuration.sidekiq_report_type == :error
          config.error_handlers << Raven::Sidekiq::ErrorHandler.new
        elsif Raven.configuration.sidekiq_report_type == :death
          config.death_handlers << Raven::Sidekiq::DeathHandler.new
        end

        config.server_middleware do |chain|
          chain.add Raven::Sidekiq::CleanupMiddleware
        end
      end
    end
  end
end

if Sidekiq::VERSION > '3'
  Raven::Sidekiq.inject
end
