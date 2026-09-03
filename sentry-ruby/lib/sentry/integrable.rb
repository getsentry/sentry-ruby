# frozen_string_literal: true

module Sentry
  module Integrable
    def register_integration(name:, version:)
      Sentry.register_integration(name, version)
      @integration_name = name
    end

    def integration_name
      @integration_name
    end

    def capture_exception(exception, **options, &block)
      options[:hint] ||= {}
      options[:hint][:integration] = integration_name

      # within an integration, we usually intercept uncaught exceptions so we set handled to false.
      options[:hint][:mechanism] ||= Sentry::Mechanism.new(type: integration_name, handled: false)

      Sentry.capture_exception(exception, **options, &block)
    end

    def capture_message(message, **options, &block)
      options[:hint] ||= {}
      options[:hint][:integration] = integration_name
      Sentry.capture_message(message, **options, &block)
    end

    def capture_check_in(slug, status, **options, &block)
      options[:hint] ||= {}
      options[:hint][:integration] = integration_name
      Sentry.capture_check_in(slug, status, **options, &block)
    end

    def count(name, value: 1, attributes: nil)
      Sentry.metrics.count(name, value: value, attributes: attributes, integration: integration_name)
    end

    def gauge(name, value, unit: nil, attributes: nil)
      Sentry.metrics.gauge(name, value, unit: unit, attributes: attributes, integration: integration_name)
    end

    def distribution(name, value, unit: nil, attributes: nil)
      Sentry.metrics.distribution(name, value, unit: unit, attributes: attributes, integration: integration_name)
    end
  end
end
