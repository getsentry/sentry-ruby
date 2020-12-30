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
        Sentry::Rails.capture_exception(exception)
      end
    end
  end
end
