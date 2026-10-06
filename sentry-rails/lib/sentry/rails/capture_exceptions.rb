# frozen_string_literal: true

require "sentry/rails/error_reporter_context"

module Sentry
  module Rails
    class CaptureExceptions < Sentry::Rack::CaptureExceptions
      include ErrorReporterContext

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

        options = {}
        options[:contexts] = execution_context if Sentry.configuration.data_collection.user_info

        Sentry::Rails.capture_exception(exception, **options).tap do |event|
          env[ERROR_EVENT_ID_KEY] = event.event_id if event
        end
      end

      def establish_propagation_context(env)
        # no-op because it was already set by CaptureContext
      end

      def start_transaction(env, scope)
        options = {
          name: scope.transaction_name,
          source: scope.transaction_source,
          op: transaction_op,
          origin: SPAN_ORIGIN
        }

        options.merge!(sampled: false) if @assets_regexp && scope.transaction_name.match?(@assets_regexp)

        start_request_transaction(env, scope, options)
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
