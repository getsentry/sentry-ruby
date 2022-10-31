module Sentry
  module Rails
    class CaptureExceptions < Sentry::Rack::CaptureExceptions
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
        "http.server".freeze
      end

      def capture_exception(exception, env)
        request = ActionDispatch::Request.new(env)

        # the exception will be swallowed by ShowExceptions middleware
        return if request.show_exceptions? && !Sentry.configuration.rails.report_rescued_exceptions
        Sentry::Rails.capture_exception(exception).tap do |event|
          env[ERROR_EVENT_ID_KEY] = event.event_id if event
        end
      end

      def start_transaction(env, scope)
        sentry_trace = env["HTTP_SENTRY_TRACE"]
        baggage = env["HTTP_BAGGAGE"]

        options = { name: scope.transaction_name, source: scope.transaction_source, op: transaction_op }

        if @assets_regexp && scope.transaction_name.match?(@assets_regexp)
          options.merge!(sampled: false)
        end

        transaction = Sentry::Transaction.from_sentry_trace(sentry_trace, baggage: baggage, **options) if sentry_trace
        Sentry.start_transaction(transaction: transaction, custom_sampling_context: { env: env }, **options)
      end
    end
  end
end
