module Sentry
  module Logging
    class Device
      attr_reader :handlers

      def initialize(options)
        @handlers = options.fetch(:handlers)
      end

      def info(message)
        handlers.each { |handler| handler.info(message) }
      end
    end
  end
end
