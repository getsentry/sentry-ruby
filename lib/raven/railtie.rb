require 'raven'
require 'rails'

module Raven
  class Railtie < ::Rails::Railtie
    initializer "raven.use_rack_middleware" do |app|
      app.config.middleware.insert 0, "Raven::Rack"
    end

    initializer 'raven.action_controller' do
      ActiveSupport.on_load :action_controller do
        require 'raven/rails/controller_methods'
        include Raven::Rails::ControllerMethods
      end
    end

    config.after_initialize do
      Raven.configure(true) do |config|
        config.logger ||= ::Rails.logger
        config.project_root ||= ::Rails.root
      end

      if defined?(::ActionDispatch::DebugExceptions)
        require 'raven/rails/middleware/debug_exceptions_catcher'
        ::ActionDispatch::DebugExceptions.send(:include, Raven::Rails::Middleware::DebugExceptionsCatcher)
      elsif defined?(::ActionDispatch::ShowExceptions)
        require 'raven/rails/middleware/debug_exceptions_catcher'
        ::ActionDispatch::ShowExceptions.send(:include, Raven::Rails::Middleware::DebugExceptionsCatcher)
      end
    end

    rake_tasks do
      require 'raven/tasks'
    end
  end
end

