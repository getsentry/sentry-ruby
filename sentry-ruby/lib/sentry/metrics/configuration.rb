# frozen_string_literal: true

module Sentry
  module Metrics
    class Configuration
      # Enable metrics usage
      # Starts a new {Sentry::Metrics::Aggregator} instance to aggregate metrics
      # and a thread to aggregate flush every 5 seconds.
      # @return [Boolean]
      attr_accessor :enabled

      def initialize
        @enabled = false
      end
    end
  end
end
