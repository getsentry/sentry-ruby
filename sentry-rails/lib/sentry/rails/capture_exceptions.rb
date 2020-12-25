module Sentry
  module Rails
    class CaptureExceptions < Sentry::Rack::CaptureExceptions
      def collect_exception(env)
        super || env["action_dispatch.exception"]
      end

      def transaction_op
        "rails.request".freeze
      end
    end
  end
end
