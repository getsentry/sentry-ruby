# frozen_string_literal: true

#
require "sentry/opentelemetry/otlp_propagator"

module Sentry
  module OpenTelemetry
    module OTLPSetup
      USER_AGENT = "sentry-ruby.otlp/#{Sentry::VERSION}"

      class << self
        def setup(config)
          @dsn = config.dsn
          @sdk_logger = config.sdk_logger
          log_debug("[OTLP] Setting up OTLP integration")

          setup_external_propagation_context
          setup_otlp_exporter if config.otlp.setup_otlp_traces_exporter
          setup_sentry_propagator if config.otlp.setup_propagator
        end

        private

        def log_debug(message)
          @sdk_logger&.debug(message)
        end

        def log_warn(message)
          @sdk_logger&.warn(message)
        end

        def setup_external_propagation_context
          log_debug("[OTLP] Setting up trace linking for all events")

          Sentry.register_external_propagation_context do
            span_context = ::OpenTelemetry::Trace.current_span.context
            span_context.valid? ? [span_context.hex_trace_id, span_context.hex_span_id] : nil
          end
        end

        def setup_otlp_exporter
          return unless @dsn

          log_debug("[OTLP] Setting up OTLP exporter")

          begin
            require "opentelemetry/exporter/otlp"
          rescue LoadError
            log_warn("[OTLP] opentelemetry-exporter-otlp gem is not installed. " \
                     "Please add it to your Gemfile to use the OTLP exporter.")
            return
          end

          endpoint = "#{@dsn.server}#{@dsn.otlp_traces_endpoint}"
          auth_header = @dsn.generate_auth_header(client: USER_AGENT)

          log_debug("[OTLP] Sending traces to #{endpoint}")

          exporter = ::OpenTelemetry::Exporter::OTLP::Exporter.new(
            endpoint: endpoint,
            headers: { "X-Sentry-Auth" => auth_header }
          )

          span_processor = ::OpenTelemetry::SDK::Trace::Export::BatchSpanProcessor.new(exporter)
          ::OpenTelemetry.tracer_provider.add_span_processor(span_processor)
        end

        def setup_sentry_propagator
          log_debug("[OTLP] Setting up propagator for distributed tracing")
          ::OpenTelemetry.propagation = OTLPPropagator.new
        end
      end
    end
  end
end
