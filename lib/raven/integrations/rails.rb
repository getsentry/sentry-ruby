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
          Raven.safely_prepend(
            "StreamingReporter",
            :from => Raven::Rails::Overrides,
            :to => ActionController::Live
          )
        end
      end
    end

    initializer 'raven.action_view' do
      ActiveSupport.on_load :action_view do
        Raven.safely_prepend(
          "StreamingReporter",
          :from => Raven::Rails::Overrides,
          :to => ActionView::StreamingTemplateRenderer::Body
        )
      end
    end

    config.before_initialize do
      Raven.configuration.logger = ::Rails.logger
    end

    config.after_initialize do
      Raven.configure do |config|
        config.project_root ||= ::Rails.root
        config.release ||= config.detect_release # if project_root has changed, need to re-check
      end

      if Raven.configuration.rails_activesupport_breadcrumbs
        require 'raven/breadcrumbs/activesupport'
        Raven::ActiveSupportBreadcrumbs.inject
      end

      if Raven.configuration.rails_report_rescued_exceptions
        require 'raven/integrations/rails/overrides/debug_exceptions_catcher'
        if defined?(::ActionDispatch::DebugExceptions)
          exceptions_class = ::ActionDispatch::DebugExceptions
        elsif defined?(::ActionDispatch::ShowExceptions)
          exceptions_class = ::ActionDispatch::ShowExceptions
        end

        Raven.safely_prepend(
          "DebugExceptionsCatcher",
          :from => Raven::Rails::Overrides,
          :to => exceptions_class
        )
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
