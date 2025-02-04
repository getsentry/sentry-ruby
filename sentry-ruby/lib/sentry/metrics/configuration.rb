# frozen_string_literal: true

module Sentry
  module Metrics
    class Configuration
      include ArgumentCheckingHelper
      include LoggingHelper

      def initialize(logger)
        @logger = logger
      end

      def method_missing(m, *args, &block)
        log_warn <<~MSG
          `config.metrics` is now deprecated and will be removed in the next major.
        MSG
      end
    end
  end
end
