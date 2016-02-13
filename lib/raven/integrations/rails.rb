require 'rails'

module Raven
  class Rails < ::Rails::Railtie
    initializer "raven.use_rack_middleware" do |app|
      app.config.middleware.insert 0, Raven::Rack
    end

    initializer 'raven.action_controller' do
      ActiveSupport.on_load :action_controller do
        require 'raven/integrations/rails/controller_methods'
        include Raven::Rails::ControllerMethods
      end
    end

    config.before_initialize do
      Raven.configure do |config|
        config.logger ||= ::Rails.logger
        config.project_root ||= ::Rails.root
        config.release = config.detect_release # if project_root has changed, need to re-check
      end
    end

    config.after_initialize do
      if Raven.configuration.catch_debugged_exceptions
        require 'raven/integrations/rails/middleware/debug_exceptions_catcher'
        if defined?(::ActionDispatch::DebugExceptions)
          exceptions_class = ::ActionDispatch::DebugExceptions
        elsif defined?(::ActionDispatch::ShowExceptions)
          exceptions_class = ::ActionDispatch::ShowExceptions
        end
        unless exceptions_class.nil?
          if RUBY_VERSION.to_f < 2.0
            exceptions_class.send(:include, Raven::Rails::Middleware::OldDebugExceptionsCatcher)
          else
            exceptions_class.send(:prepend, Raven::Rails::Middleware::DebugExceptionsCatcher)
          end
        end
      end
    end

    rake_tasks do
      require 'raven/integrations/tasks'
    end

    if defined?(runner)
      runner do
        Raven.capture
      end
    end
  end
end
