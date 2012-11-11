require 'raven/rails/action_controller_catcher'

module Raven
  module Rails
    def self.initialize

      if defined?(ActionController::Base)
        ActionController::Base.send(:include, Raven::Rails::ActionControllerCatcher)
      end

      if defined?(::Rails.configuration) && ::Rails.configuration.respond_to?(:middleware)
        ::Rails.configuration.middleware.insert_after 'ActionController::Failsafe', Raven::Rack
      end

      Raven.configure(true) do |config|
        config.logger ||= if defined?(::Rails.logger)
          ::Rails.logger
        elsif defined?(RAILS_DEFAULT_LOGGER)
          RAILS_DEFAULT_LOGGER
        end
      end
      
    end
  end
end

Raven::Rails.initialize