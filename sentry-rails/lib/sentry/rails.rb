# frozen_string_literal: true

require "rails"
require "sentry-ruby"
require "sentry/integrable"
require "sentry/rails/tracing"
require "sentry/rails/configuration"
require "sentry/rails/active_job_extension"
require "sentry/rails/structured_logging"
require "sentry/rails/engine"
require "sentry/rails/railtie"
require "sentry/rails/good_job_cron"
require "sentry/rails/solid_queue_recurring"

module Sentry
  module Rails
    extend Integrable
    register_integration name: "rails", version: Sentry::Rails::VERSION

    DEFAULT_ACTIVE_JOB_EXTENSION = ActiveJobExtension.new
    private_constant :DEFAULT_ACTIVE_JOB_EXTENSION

    # Returns whether sentry-rails reports ActiveJob jobs run through the given
    # queue adapter, in which case the backend gem should not report them itself.
    # The result depends on the current configuration, so check it when a job is
    # handled rather than caching it.
    #
    # @param adapter_class_name [String, Class]
    # @return [Boolean]
    def self.active_job_owns_adapter?(adapter_class_name)
      Sentry.initialized? && !Sentry.configuration.rails.skippable_job_adapters.include?(adapter_class_name.to_s)
    end

    # Registers the extension for ActiveJob jobs run through the given queue
    # adapter. Raises ArgumentError if it is not an {ActiveJobExtension}.
    #
    # @param adapter [Symbol] the adapter name, such as `:sidekiq`
    # @param extension [ActiveJobExtension]
    # @return [ActiveJobExtension]
    def self.register_active_job_extension(adapter, extension)
      unless extension.is_a?(ActiveJobExtension)
        raise ArgumentError, "ActiveJob extension must be an instance of #{ActiveJobExtension}, got #{extension.inspect}"
      end

      active_job_extensions[adapter.to_sym] = extension
    end

    # Returns the extension for the job class' queue adapter, or the default
    # {ActiveJobExtension} when none is registered.
    #
    # @param job_class [Class]
    # @return [ActiveJobExtension]
    def self.active_job_extension_for(job_class)
      active_job_extensions.fetch(ActiveJobExtension.adapter_name(job_class), DEFAULT_ACTIVE_JOB_EXTENSION)
    end

    # Returns the registered extensions by adapter name.
    #
    # @return [Hash{Symbol => ActiveJobExtension}]
    def self.active_job_extensions
      @active_job_extensions ||= {}
    end
  end
end
