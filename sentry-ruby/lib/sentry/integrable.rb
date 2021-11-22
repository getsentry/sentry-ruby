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
      Sentry.capture_exception(exception, **options, &block)
    end

    def capture_message(message, **options, &block)
      options[:hint] ||= {}
      options[:hint][:integration] = integration_name
      Sentry.capture_message(message, **options, &block)
    end
  end
end
