require "rails"
require "sentry/rails/capture_exceptions"
require "sentry/rails/backtrace_cleaner"
require "sentry/rails/controller_methods"
require "sentry/rails/controller_transaction"
require "sentry/rails/active_job"
require "sentry/rails/overrides/streaming_reporter"

module Sentry
  class Railtie < ::Rails::Railtie
    initializer "sentry.use_rack_middleware" do |app|
      app.config.middleware.insert 0, Sentry::Rails::CaptureExceptions
    end

    initializer 'sentry.action_controller' do
      ActiveSupport.on_load :action_controller do
        include Sentry::Rails::ControllerMethods
        include Sentry::Rails::ControllerTransaction
        ActionController::Live.send(:prepend, Sentry::Rails::Overrides::StreamingReporter)
      end
    end

    initializer 'sentry.action_view' do
      ActiveSupport.on_load :action_view do
        ActionView::StreamingTemplateRenderer::Body.send(:prepend, Sentry::Rails::Overrides::StreamingReporter)
      end
    end

    config.after_initialize do
      Sentry.configuration.logger = ::Rails.logger

      setup_backtrace_cleanup_callback
      inject_breadcrumbs_logger
      override_exceptions_handling
      activate_tracing
    end

    def inject_breadcrumbs_logger
      if Sentry.configuration.breadcrumbs_logger.include?(:active_support_logger)
        require 'sentry/rails/breadcrumb/active_support_logger'
        Sentry::Rails::Breadcrumb::ActiveSupportLogger.inject
      end
    end

    def setup_backtrace_cleanup_callback
      backtrace_cleaner = Sentry::Rails::BacktraceCleaner.new

      Sentry.configuration.backtrace_cleanup_callback = lambda do |backtrace|
        backtrace_cleaner.clean(backtrace)
      end
    end

    def override_exceptions_handling
      if Sentry.configuration.rails.report_rescued_exceptions
        require 'sentry/rails/overrides/debug_exceptions_catcher'
        if defined?(::ActionDispatch::DebugExceptions)
          exceptions_class = ::ActionDispatch::DebugExceptions
        elsif defined?(::ActionDispatch::ShowExceptions)
          exceptions_class = ::ActionDispatch::ShowExceptions
        end

        exceptions_class.send(:prepend, Sentry::Rails::Overrides::DebugExceptionsCatcher)
      end
    end

    def activate_tracing
      if Sentry.configuration.tracing_enabled?
        Sentry::Rails::Tracing.subscribe_tracing_events
        Sentry::Rails::Tracing.patch_active_support_notifications
      end
    end

    initializer 'sentry.active_job' do
      ActiveSupport.on_load :active_job do
        require 'sentry/rails/active_job'
      end
    end
  end
end
