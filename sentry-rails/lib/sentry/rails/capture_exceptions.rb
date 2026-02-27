# frozen_string_literal: true

module Sentry
  module Rails
    class CaptureExceptions < Sentry::Rack::CaptureExceptions
      RAILS_7_1 = Gem::Version.new(::Rails.version) >= Gem::Version.new("7.1.0.alpha")
      SPAN_ORIGIN = "auto.http.rails"

      def initialize(_)
        super

        if Sentry.initialized?
          @assets_regexp = Sentry.configuration.rails.assets_regexp
        end
      end

      private

      def collect_exception(env)
        return nil if env["sentry.already_captured"]
        super || env["action_dispatch.exception"] || env["sentry.rescued_exception"]
      end

      def transaction_op
        "http.server"
      end

      def capture_exception(exception, env)
        # the exception will be swallowed by ShowExceptions middleware
        return unless Sentry.initialized?
        return if show_exceptions?(exception, env) && !Sentry.configuration.rails.report_rescued_exceptions

        Sentry::Rails.capture_exception(exception).tap do |event|
          env[ERROR_EVENT_ID_KEY] = event.event_id if event
        end
      end

      def start_transaction(env, scope)
        super do |options|
          if @assets_regexp && scope.transaction_name.match?(@assets_regexp)
            options.merge!(sampled: false)
          end
        end
      end

      def show_exceptions?(exception, env)
        request = ActionDispatch::Request.new(env)

        if RAILS_7_1
          ActionDispatch::ExceptionWrapper.new(nil, exception).show?(request)
        else
          request.show_exceptions?
        end
      end

      def status_code_for_exception(exception)
        ActionDispatch::ExceptionWrapper.status_code_for_exception(exception.class.name)
      end
    end
  end
end
