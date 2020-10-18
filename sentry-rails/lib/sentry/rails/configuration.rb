module Sentry
  class Configuration
    attr_reader :rails

    def post_initialization_callback
      @rails = Sentry::Rails::Configuration.new
    end
  end

  module Rails
    class Configuration
      # Rails catches exceptions in the ActionDispatch::ShowExceptions or
      # ActionDispatch::DebugExceptions middlewares, depending on the environment.
      # When `rails_report_rescued_exceptions` is true (it is by default), Sentry
      # will report exceptions even when they are rescued by these middlewares.
      attr_accessor :report_rescued_exceptions

      def initialize
        @report_rescued_exceptions = true
      end
    end
  end
end
