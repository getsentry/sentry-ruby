module Sentry
  module Rails
    class CaptureExceptions < Sentry::Rack::CaptureExceptions
      def initialize(app)
        super

        if defined?(::Sprockets::Rails)
          @assets_regex = %r(\A/{0,2}#{::Rails.application.config.assets.prefix})
        end
      end

      private

      def collect_exception(env)
        return nil if env["sentry.already_captured"]
        super || env["action_dispatch.exception"] || env["sentry.rescued_exception"]
      end

      def transaction_op
        "rails.request".freeze
      end

      def capture_exception(exception)
        current_scope = Sentry.get_current_scope

        if original_transaction = current_scope.rack_env["sentry.original_transaction"]
          current_scope.set_transaction_name(original_transaction)
        end

        Sentry::Rails.capture_exception(exception)
      end

      def start_transaction(env, scope)
        sentry_trace = env["HTTP_SENTRY_TRACE"]
        options = { name: scope.transaction_name, op: transaction_op }

        if @assets_regex && scope.transaction_name.match?(@assets_regex)
          options.merge!(sampled: false)
        end

        transaction = Sentry::Transaction.from_sentry_trace(sentry_trace, **options) if sentry_trace
        Sentry.start_transaction(transaction: transaction, custom_sampling_context: { env: env }, **options)
      end
    end
  end
end
