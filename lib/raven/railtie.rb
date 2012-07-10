require 'raven'
require 'rails'

module Raven
  class Railtie < ::Rails::Railtie
    initializer "raven.use_rack_middleware" do |app|
      app.config.middleware.use "Raven::Rack" unless defined?(::ActionDispatch::DebugExceptions)
    end

    config.after_initialize do
      Raven.configure(true) do |config|
        config.logger ||= ::Rails.logger
      end

      if defined?(::ActionDispatch::DebugExceptions)
        require 'raven/rails/middleware/debug_exceptions_catcher'
        ::ActionDispatch::DebugExceptions.send(:include, Raven::Rails::Middleware::DebugExceptionsCatcher)
      else
        Rails.configuration.middleware.use "Raven::Rack"
      end
    end
  end
end
