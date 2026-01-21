# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Sentry::OpenTelemetry::OTLPSetup do
  before do
    perform_otel_setup
  end

  describe '.setup' do
    it 'returns early when config is nil and Sentry not initialized' do
      expect(described_class.setup).to be_nil
    end

    it 'returns early when OTLP is not enabled' do
      perform_basic_setup do |config|
        config.otlp.enabled = false
      end

      expect(::OpenTelemetry).not_to receive(:propagation=)
      described_class.setup
    end

    context 'with setup_propagator enabled' do
      before do
        perform_basic_setup do |config|
          config.otlp.enabled = true
          config.otlp.setup_propagator = true
        end
      end

      it 'sets up the OTLP propagator' do
        described_class.setup

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
        described_class.setup
      end
    end

    context 'with event processor' do
      before do
        perform_basic_setup do |config|
          config.otlp.enabled = true
        end
      end

      it 'adds a global event processor' do
        processor_count_before = Sentry::Scope.global_event_processors.size
        described_class.setup
        processor_count_after = Sentry::Scope.global_event_processors.size

        expect(processor_count_after).to eq(processor_count_before + 1)
      end
    end
  end
end
