# frozen_string_literal: true

module Sentry
  module Metrics
    class << self
      def method_missing(m, *args, &block)
        return unless Sentry.initialized?

        Sentry.logger.warn(LOGGER_PROGNAME) do
          "`Sentry::Metrics` is now deprecated and will be removed in the next major."
        end
      end
    end
  end
end
