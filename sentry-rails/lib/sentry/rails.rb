# frozen_string_literal: true

require "rails"
require "sentry-ruby"
require "sentry/integrable"
require "sentry/rails/tracing"
require "sentry/rails/configuration"
require "sentry/rails/structured_logging"
require "sentry/rails/engine"
require "sentry/rails/railtie"

module Sentry
  module Rails
    extend Integrable
    register_integration name: "rails", version: Sentry::Rails::VERSION

    # Returns whether sentry-rails' ActiveJob integration reports jobs run
    # through the given queue adapter.
    #
    # When it returns true, the integration captures errors from those jobs,
    # records their queue.process transactions and queue.publish spans,
    # propagates traces, and consults extensions registered with
    # {Sentry.register_job_extension}. A backend gem should then not report the
    # same ActiveJob jobs itself.
    #
    # The result depends on {Sentry.initialized?} and the current configuration,
    # so it can change after {Sentry.init}. Call it when a job is handled rather
    # than caching the result at load time.
    #
    # @param adapter_class_name [String, Class] the ActiveJob queue adapter's
    #   class name, such as "ActiveJob::QueueAdapters::SidekiqAdapter", or the
    #   adapter class itself. It is compared against
    #   +config.rails.skippable_job_adapters+.
    # @return [Boolean] true if the SDK is initialized and the adapter is not
    #   listed in +config.rails.skippable_job_adapters+, false otherwise
    def self.active_job_owns_adapter?(adapter_class_name)
      Sentry.initialized? && !Sentry.configuration.rails.skippable_job_adapters.include?(adapter_class_name.to_s)
    end
  end
end
