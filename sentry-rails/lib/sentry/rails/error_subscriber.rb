module Sentry
  module Rails
    # This is not a user-facing class. You should use it with Rails 7.0's error reporter feature and its interfaces.
    # See https://github.com/rails/rails/blob/main/activesupport/lib/active_support/error_reporter.rb for more information.
    class ErrorSubscriber
      def report(error, handled:, severity:, context:)
        Sentry::Rails.capture_exception(error, level: severity, contexts: { "rails.error" => context }, tags: { handled: handled })
      end
    end
  end
end
