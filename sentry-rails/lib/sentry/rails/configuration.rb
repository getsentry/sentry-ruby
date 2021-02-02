module Sentry
  class Configuration
    attr_reader :rails

    add_post_initialization_callback do
      @rails = Sentry::Rails::Configuration.new
      @excluded_exceptions = @excluded_exceptions.concat(Sentry::Rails::IGNORE_DEFAULT)
    end
  end

  module Rails
    IGNORE_DEFAULT = [
      'AbstractController::ActionNotFound',
      'ActionController::BadRequest',
      'ActionController::InvalidAuthenticityToken',
      'ActionController::InvalidCrossOriginRequest',
      'ActionController::MethodNotAllowed',
      'ActionController::NotImplemented',
      'ActionController::ParameterMissing',
      'ActionController::RoutingError',
      'ActionController::UnknownAction',
      'ActionController::UnknownFormat',
      'ActionDispatch::Http::MimeNegotiation::InvalidType',
      'ActionController::UnknownHttpMethod',
      'ActionDispatch::Http::Parameters::ParseError',
      'ActiveRecord::RecordNotFound'
    ].freeze
    class Configuration
      # Rails catches exceptions in the ActionDispatch::ShowExceptions or
      # ActionDispatch::DebugExceptions middlewares, depending on the environment.
      # When `rails_report_rescued_exceptions` is true (it is by default), Sentry
      # will report exceptions even when they are rescued by these middlewares.
      attr_accessor :report_rescued_exceptions

      # Some adapters, like sidekiq, already have their own sentry integration.
      # In those cases, we should disable ActiveJob's reporting to avoid duplicated reports.
      attr_accessor :ignored_active_job_adapters

      def initialize
        @report_rescued_exceptions = true
        # TODO: Remove this in 4.2.0
        @ignored_active_job_adapters = []
      end
    end
  end
end
