module Sentry
  module Rails
    class CaptureException < Sentry::Rack::CaptureException
      def collect_exception(env)
        super || env["action_dispatch.exception"]
      end
    end
  end
end
