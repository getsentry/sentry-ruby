# frozen_string_literal: true
#
require "sentry/opentelemetry/otlp_propagator"

module Sentry
  module OpenTelemetry
    module OTLPSetup
      class << self
        def setup(config = nil)
          config ||= Sentry.configuration if Sentry.initialized?
          return unless config && config.otlp.enabled

          @config = config
          log_debug("[OTLP] Setting up OTLP integration")

          setup_event_processor
          setup_otlp_exporter if config.otlp.setup_otlp_traces_exporter
          setup_sentry_propagator if config.otlp.setup_propagator
          setup_exception_capture if config.otlp.capture_exceptions
        end

        private

        def log_debug(message)
          @config&.sdk_logger&.debug(message)
        end

        def log_warn(message)
          @config&.sdk_logger&.warn(message)
        end

        def setup_event_processor
          log_debug("[OTLP] Setting up trace linking for all events")

          Sentry.add_global_event_processor do |event, _hint|
            span_context = ::OpenTelemetry::Trace.current_span.context
            next event unless span_context.valid?

            event.contexts[:trace] ||= {}
            event.contexts[:trace][:trace_id] ||= span_context.hex_trace_id
            event.contexts[:trace][:span_id] ||= span_context.hex_span_id
            event
          end
        end

        def setup_otlp_exporter
          dsn = @config.dsn
          return unless dsn

          log_debug("[OTLP] Setting up OTLP exporter")

          begin
            require "opentelemetry/exporter/otlp"
          rescue LoadError
            log_warn("[OTLP] opentelemetry-exporter-otlp gem is not installed. " \
                     "Please add it to your Gemfile to use the OTLP exporter.")
            return
          end

          endpoint = "#{dsn.server}#{dsn.otlp_traces_endpoint}"
          auth_header = generate_auth_header(dsn)

          log_debug("[OTLP] Sending traces to #{endpoint}")

          exporter = ::OpenTelemetry::Exporter::OTLP::Exporter.new(
            endpoint: endpoint,
            headers: { "X-Sentry-Auth" => auth_header }
          )

          span_processor = ::OpenTelemetry::SDK::Trace::Export::BatchSpanProcessor.new(exporter)

          tracer_provider = ::OpenTelemetry.tracer_provider
          if tracer_provider.respond_to?(:add_span_processor)
            tracer_provider.add_span_processor(span_processor)
          else
            log_warn("[OTLP] TracerProvider does not support add_span_processor. " \
                     "OTLP exporter was not added.")
          end
        end

        def setup_sentry_propagator
          log_debug("[OTLP] Setting up propagator for distributed tracing")
          ::OpenTelemetry.propagation = OTLPPropagator.new
        end

        def setup_exception_capture
          return if @exception_capture_patched

          log_debug("[OTLP] Setting up exception capture")

          begin
            original_method = ::OpenTelemetry::SDK::Trace::Span.instance_method(:record_exception)

            ::OpenTelemetry::SDK::Trace::Span.define_method(:record_exception) do |exception, attributes: nil|
              if Sentry.initialized? && Sentry.configuration.otlp.capture_exceptions
                Sentry.capture_exception(exception, mechanism: { type: "otlp", handled: false })
              end
              original_method.bind(self).call(exception, attributes: attributes)
            end

            @exception_capture_patched = true
          rescue StandardError => e
            log_warn("[OTLP] Failed to patch record_exception: #{e.message}")
          end
        end

        def generate_auth_header(dsn)
          now = Sentry.utc_now.to_i
          fields = {
            "sentry_version" => Sentry::Transport::PROTOCOL_VERSION,
            "sentry_client" => "sentry.ruby.otlp/#{Sentry::OpenTelemetry::VERSION}",
            "sentry_timestamp" => now,
            "sentry_key" => dsn.public_key
          }
          fields["sentry_secret"] = dsn.secret_key if dsn.secret_key
          "Sentry " + fields.map { |k, v| "#{k}=#{v}" }.join(", ")
        end
      end
    end
  end
end
