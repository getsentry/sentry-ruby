# frozen_string_literal: true

require "sentry/opentelemetry/otlp_setup"

module Sentry
  class Configuration
    # OTLP related configuration.
    # @return [OTLP::Configuration]
    attr_reader :otlp

    after(:initialize) do
      @otlp = OTLP::Configuration.new
    end

    after(:configured) do
      Sentry::OpenTelemetry::OTLPSetup.setup(self) if otlp.enabled
    end
  end

  module OTLP
    class Configuration
      attr_accessor :enabled
      attr_accessor :setup_otlp_traces_exporter
      attr_accessor :setup_propagator

      def initialize
        @enabled = false
        @setup_otlp_traces_exporter = true
        @setup_propagator = true
      end
    end
  end
end
