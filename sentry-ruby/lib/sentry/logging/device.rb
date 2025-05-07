# frozen_string_literal: true

module Sentry
  module Logging
    class Device
      attr_reader :handlers

      def initialize(options)
        @handlers = options.fetch(:handlers)
      end

      def trace(message, payload = {})
        log(:trace, message, payload)
      end

      def debug(message, payload = {})
        log(:debug, message, payload)
      end

      def info(message, payload = {})
        log(:info, message, payload)
      end

      def warn(message, payload = {})
        log(:warn, message, payload)
      end

      def error(message, payload = {})
        log(:error, message, payload)
      end

      def fatal(message, payload = {})
        log(:fatal, message, payload)
      end

      def log(level, message, payload)
        handlers.each do |handler|
          case handler
          when Sentry::Logger
            handler.public_send(level, message)
          else
            handler.public_send(level, message, payload)
          end
        end
      end
    end
  end
end
