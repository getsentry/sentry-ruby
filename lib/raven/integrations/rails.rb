require 'rails'

module Raven
  class Rails < ::Rails::Railtie
    require 'raven/integrations/rails/overrides/streaming_reporter'
    require 'raven/integrations/rails/controller_methods'

    initializer "raven.use_rack_middleware" do |app|
      app.config.middleware.insert 0, Raven::Rack
    end

    initializer 'raven.action_controller' do
      ActiveSupport.on_load :action_controller do
        include Raven::Rails::ControllerMethods
        if ::Rails::VERSION::STRING >= "4.0.0"
          Raven.rails_safely_prepend("StreamingReporter", :to => ActionController::Live)
        end
      end
    end

    initializer 'raven.action_view' do
      ActiveSupport.on_load :action_view do
        Raven.rails_safely_prepend("StreamingReporter", :to => ActionView::StreamingTemplateRenderer::Body)
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
      if Raven.configuration.rails_report_rescued_exceptions
        require 'raven/integrations/rails/overrides/debug_exceptions_catcher'
        if defined?(::ActionDispatch::DebugExceptions)
          exceptions_class = ::ActionDispatch::DebugExceptions
        elsif defined?(::ActionDispatch::ShowExceptions)
          exceptions_class = ::ActionDispatch::ShowExceptions
        end
        Raven.rails_safely_prepend("DebugExceptionsCatcher", :to => exceptions_class)
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
