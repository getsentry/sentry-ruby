# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Sentry::OpenTelemetry::OTLPSetup do
  before do
    perform_otel_setup
  end

  describe '.setup' do
    context 'with setup_propagator enabled' do
      before do
        perform_basic_setup do |config|
          config.otlp.enabled = true
          config.otlp.setup_propagator = true
        end
      end

      it 'sets up the OTLP propagator' do
        described_class.setup(Sentry.configuration)

        expect(::OpenTelemetry.propagation).to be_a(Sentry::OpenTelemetry::OTLPPropagator)
      end
    end

    context 'with setup_otlp_traces_exporter enabled' do
      before do
        perform_basic_setup do |config|
          config.otlp.enabled = true
        end
      end

      it 'logs a warning when opentelemetry-exporter-otlp is not installed' do
        allow_any_instance_of(Object).to receive(:require).with("opentelemetry/exporter/otlp").and_raise(LoadError)

        expect(Sentry.configuration.sdk_logger).to receive(:warn).with(/opentelemetry-exporter-otlp gem is not installed/)
        described_class.setup(Sentry.configuration)
      end
    end

    context 'with external propagation context' do
      before do
        perform_basic_setup do |config|
          config.otlp.enabled = true
        end
      end

      it 'registers external propagation context for trace linking' do
        expect(Sentry).to receive(:register_external_propagation_context)
        described_class.setup(Sentry.configuration)
      end

      context 'when OpenTelemetry span context is valid' do
        it 'returns trace_id and span_id from current span' do
          described_class.setup(Sentry.configuration)

          tracer = ::OpenTelemetry.tracer_provider.tracer('test')
          tracer.in_span('test_span') do
            span_context = ::OpenTelemetry::Trace.current_span.context
            expected_trace_id = span_context.hex_trace_id
            expected_span_id = span_context.hex_span_id

            trace_id, span_id = Sentry.get_external_propagation_context

            expect(trace_id).to eq(expected_trace_id)
            expect(span_id).to eq(expected_span_id)
          end
        end
      end

      context 'when OpenTelemetry span context is invalid' do
        it 'returns nil' do
          described_class.setup(Sentry.configuration)

          result = Sentry.get_external_propagation_context
          expect(result).to be_nil
        end
      end
    end
  end
end
