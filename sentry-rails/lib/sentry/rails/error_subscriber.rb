module Sentry
  module Rails
    # This is not a user-facing class. You should use it with Rails 7.0's error reporter feature and its interfaces.
    # See https://github.com/rails/rails/blob/main/activesupport/lib/active_support/error_reporter.rb for more information.
    class ErrorSubscriber
      def report(error, handled:, severity:, context:)
        # a component may already have an integration to capture exceptions while its operation is also wrapped inside an `app.executor.wrap` (e.g. ActionCable)
        # in such condition, the exception would be captured repeatedly. it usually happens in this order:
        #
        # 1. exception captured and reported by the component integration and re-raised
        # 2. exception captured by the executor, which then reports it with executor.error_reporter
        #
        # and because there's no direct communication between the 2 callbacks, we need a way to identify if an exception has been captured before
        # using a Sentry-specific intance variable should be the last impactful way
        return if error.instance_variable_get(:@__sentry_captured)
        Sentry::Rails.capture_exception(error, level: severity, contexts: { "rails.error" => context }, tags: { handled: handled })
      end
    end
  end
end
