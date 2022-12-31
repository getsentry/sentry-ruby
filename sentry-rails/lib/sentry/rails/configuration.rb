require "sentry/rails/tracing/action_controller_subscriber"
require "sentry/rails/tracing/action_view_subscriber"
require "sentry/rails/tracing/active_record_subscriber"
require "sentry/rails/tracing/active_storage_subscriber"

module Sentry
  class Configuration
    attr_reader :rails

    add_post_initialization_callback do
      @rails = Sentry::Rails::Configuration.new
      @excluded_exceptions = @excluded_exceptions.concat(Sentry::Rails::IGNORE_DEFAULT)

      if ::Rails.logger
        @logger = ::Rails.logger
      else
        @logger.warn(Sentry::LOGGER_PROGNAME) do
          <<~MSG
          sentry-rails can't detect Rails.logger. it may be caused by misplacement of the SDK initialization code
          please make sure you place the Sentry.init block under the `config/initializers` folder, e.g. `config/initializers/sentry.rb`
          MSG
        end
      end
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
      # Rails 7.0 introduced a new error reporter feature, which the SDK once opted-in by default.
      # But after receiving multiple issue reports, the integration seemed to cause serious troubles to some users.
      # So the integration is now controlled by this configuration, which is disabled (false) by default.
      # More information can be found from: https://github.com/rails/rails/pull/43625#issuecomment-1072514175
      attr_accessor :register_error_subscriber

      # Rails catches exceptions in the ActionDispatch::ShowExceptions or
      # ActionDispatch::DebugExceptions middlewares, depending on the environment.
      # When `rails_report_rescued_exceptions` is true (it is by default), Sentry
      # will report exceptions even when they are rescued by these middlewares.
      attr_accessor :report_rescued_exceptions

      # Some adapters, like sidekiq, already have their own sentry integration.
      # In those cases, we should skip ActiveJob's reporting to avoid duplicated reports.
      attr_accessor :skippable_job_adapters

      attr_accessor :tracing_subscribers

      # sentry-rails by default skips asset request' transactions by checking if the path matches
      #
      # ```rb
      # %r(\A/{0,2}#{::Rails.application.config.assets.prefix})
      # ```
      #
      # If you want to use a different pattern, you can configure the `assets_regexp` option like:
      #
      # ```rb
      # Sentry.init do |config|
      #   config.rails.assets_regexp = /my_regexp/
      # end
      # ```
      attr_accessor :assets_regexp

      def initialize
        @register_error_subscriber = false
        @report_rescued_exceptions = true
        @skippable_job_adapters = []
        @assets_regexp = if defined?(::Sprockets::Rails)
          %r(\A/{0,2}#{::Rails.application.config.assets.prefix})
        end
        @tracing_subscribers = Set.new([
          Sentry::Rails::Tracing::ActionViewSubscriber,
          Sentry::Rails::Tracing::ActiveRecordSubscriber,
          Sentry::Rails::Tracing::ActiveStorageSubscriber
        ])
      end
    end
  end
end
