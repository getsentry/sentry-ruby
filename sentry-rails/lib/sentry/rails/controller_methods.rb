module Sentry
  module Rails
    module ControllerMethods
      def capture_message(message, options = {})
        Sentry::Rack.capture_message(message, request.env, options)
      end

      def capture_exception(exception, options = {})
        Sentry::Rack.capture_exception(exception, request.env, options)
      end
    end
  end
end
