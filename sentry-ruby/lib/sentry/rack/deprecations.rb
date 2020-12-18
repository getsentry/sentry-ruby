module Sentry
  module Rack
    class DeprecatedMiddleware
      def initialize(_)
        raise Sentry::Error.new <<~MSG

You're seeing this message because #{self.class} has been replaced by Sentry::Rack::CaptureExceptions.
Removing this middleware from your app and upgrading sentry-rails to 4.1.0+ should solve the issue.
        MSG
      end
    end

    class Tracing < DeprecatedMiddleware
    end

    class CaptureException < DeprecatedMiddleware
    end
  end
end
