module Sentry
  module Rails
    # This is not a user-facing class. You should use it with Rails 7.0's error reporter feature and its interfaces.
    # See https://github.com/rails/rails/blob/main/activesupport/lib/active_support/error_reporter.rb for more information.
    class ErrorSubscriber
      SKIP_SOURCES = Regexp.union([/.*_cache_store.active_support/])

      def report(error, handled:, severity:, context:, source: nil)
        tags = { handled: handled }

        if source
          return if SKIP_SOURCES.match?(source)
          tags[:source] = source
        end

        Sentry::Rails.capture_exception(error, level: severity, contexts: { "rails.error" => context }, tags: tags)
      end
    end
  end
end
