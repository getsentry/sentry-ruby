module Sentry
  module Logging
    class Device
      attr_reader :handlers

      def initialize(options)
        @handlers = options.fetch(:handlers)
      end

      def trace(message)
        log(:trace, message)
      end

      def debug(message)
        log(:debug, message)
      end

      def info(message)
        log(:info, message)
      end

      def warn(message)
        log(:warn, message)
      end

      def error(message)
        log(:error, message)
      end

      def fatal(message)
        log(:fatal, message)
      end

      def log(level, message)
        handlers.each { |handler| handler.public_send(level, message) }
      end
    end
  end
end
