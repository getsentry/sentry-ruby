# frozen_string_literal: true

module Sentry
  module OTLP
    class Configuration
      attr_accessor :enabled
      attr_accessor :setup_otlp_traces_exporter
      attr_accessor :setup_propagator
      attr_accessor :capture_exceptions

      def initialize
        @enabled = false
        @setup_otlp_traces_exporter = true
        @setup_propagator = true
        @capture_exceptions = false
      end

      def enabled?
        @setup_otlp_traces_exporter || @setup_propagator
      end
    end
  end
end
