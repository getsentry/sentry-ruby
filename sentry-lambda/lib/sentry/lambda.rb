require "sentry-ruby"
require "sentry/integrable"
require "sentry/lambda/capture_exceptions"

module Sentry
  module Lambda
    extend Integrable
    register_integration name: 'lambda', version: Sentry::Lambda::VERSION

    def self.wrap_handler(event:, context:, capture_timeout_warning: false)
      CaptureExceptions.new(
        aws_event: event,
        aws_context: context,
        capture_timeout_warning: capture_timeout_warning
      ).call do
        yield
      end
    end
  end
end
