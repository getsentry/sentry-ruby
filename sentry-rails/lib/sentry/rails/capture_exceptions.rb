module Sentry
  module Rails
    class CaptureExceptions < Sentry::Rack::CaptureExceptions
      private

      def collect_exception(env)
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
    end
  end
end
