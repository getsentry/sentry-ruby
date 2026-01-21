# frozen_string_literal: true

require "sentry-ruby"
require "opentelemetry-sdk"

require "sentry/opentelemetry/version"
require "sentry/opentelemetry/span_processor"
require "sentry/opentelemetry/propagator"
require "sentry/opentelemetry/otlp_setup"

Sentry::Configuration.after(:configured) do
  Sentry::OpenTelemetry::OTLPSetup.setup(self) if otlp.enabled?
end
