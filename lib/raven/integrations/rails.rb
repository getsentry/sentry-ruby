require 'rails'

module Raven
  class Rails < ::Rails::Railtie
    require 'raven/integrations/rails/overrides/streaming_reporter'
    require 'raven/integrations/rails/controller_methods'
    require 'raven/integrations/rails/controller_transaction'
    require 'raven/integrations/rails/backtrace_cleaner'
    require 'raven/integrations/rack'

    initializer "raven.use_rack_middleware" do |app|
      app.config.middleware.insert 0, Raven::Rack
    end

    initializer 'raven.action_controller' do
      ActiveSupport.on_load :action_controller do
        include Raven::Rails::ControllerMethods
        include Raven::Rails::ControllerTransaction
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

      backtrace_cleaner = Raven::Rails::BacktraceCleaner.new

      Raven.configuration.backtrace_cleanup_callback = lambda do |backtrace|
        backtrace_cleaner.clean(backtrace)
      end
    end

    config.after_initialize do
      if Raven.configuration.breadcrumbs_logger.include?(:active_support_logger) ||
         Raven.configuration.rails_activesupport_breadcrumbs

        require 'raven/breadcrumbs/active_support_logger'
        Raven::Breadcrumbs::ActiveSupportLogger.inject
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

    initializer 'raven.active_job' do
      ActiveSupport.on_load :active_job do
        require 'raven/integrations/rails/active_job'
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
