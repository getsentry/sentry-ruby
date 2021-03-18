require "rails"
require "sentry/rails/capture_exceptions"
require "sentry/rails/rescued_exception_interceptor"
require "sentry/rails/backtrace_cleaner"

module Sentry
  class Railtie < ::Rails::Railtie
    # middlewares can't be injected after initialize
    initializer "sentry.use_rack_middleware" do |app|
      # need to be placed at first to capture as many errors as possible
      app.config.middleware.insert 0, Sentry::Rails::CaptureExceptions
      # need to be placed at last to smuggle app exceptions via env
      app.config.middleware.use(Sentry::Rails::RescuedExceptionInterceptor)
    end

    config.after_initialize do |app|
      next unless Sentry.initialized?

      configure_project_root
      configure_sentry_logger
      configure_trusted_proxies
      extend_controller_methods if defined?(ActionController)
      extend_active_job if defined?(ActiveJob)
      patch_background_worker if defined?(ActiveRecord)
      override_streaming_reporter if defined?(ActionView)
      override_file_handler if defined?(ActionDispatch) && app.config.public_file_server.enabled
      setup_backtrace_cleanup_callback
      inject_breadcrumbs_logger
      activate_tracing
    end

    def configure_project_root
      Sentry.configuration.project_root = ::Rails.root.to_s
    end

    def configure_sentry_logger
      Sentry.configuration.logger = ::Rails.logger
    end

    def configure_trusted_proxies
      Sentry.configuration.trusted_proxies += Array(::Rails.application.config.action_dispatch.trusted_proxies)
    end

    def extend_active_job
      require "sentry/rails/active_job"
      ActiveJob::Base.send(:prepend, Sentry::Rails::ActiveJobExtensions)
    end

    def extend_controller_methods
      require "sentry/rails/controller_methods"
      require "sentry/rails/controller_transaction"
      require "sentry/rails/overrides/streaming_reporter"

      ActiveSupport.on_load :action_controller do
        include Sentry::Rails::ControllerMethods
        include Sentry::Rails::ControllerTransaction
        ActionController::Live.send(:prepend, Sentry::Rails::Overrides::StreamingReporter)
      end
    end

    def patch_background_worker
      require "sentry/rails/background_worker"
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

    def override_streaming_reporter
      require "sentry/rails/overrides/streaming_reporter"

      ActiveSupport.on_load :action_view do
        ActionView::StreamingTemplateRenderer::Body.send(:prepend, Sentry::Rails::Overrides::StreamingReporter)
      end
    end

    def override_file_handler
      require "sentry/rails/overrides/file_handler"

      ActiveSupport.on_load :action_controller do
        ActionDispatch::FileHandler.send(:prepend, Sentry::Rails::Overrides::FileHandler)
      end
    end

    def activate_tracing
      if Sentry.configuration.tracing_enabled?
        Sentry::Rails::Tracing.subscribe_tracing_events
        Sentry::Rails::Tracing.patch_active_support_notifications
      end
    end
  end
end
