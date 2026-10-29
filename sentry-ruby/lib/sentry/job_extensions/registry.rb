# frozen_string_literal: true

module Sentry
  module JobExtensions
    # Holds the registered {Extension} instances, in registration order, and
    # selects the one that handles a given job.
    #
    # The registry is process-wide and available through {Sentry.job_extensions}.
    # It is independent of {Sentry.init}: extensions can be registered before or
    # after the SDK is initialized, and stay registered when it is re-initialized.
    class Registry
      include LoggingHelper

      def initialize(registry: nil, default_extension: nil)
        @registry = registry
        @default_extension = default_extension
        @mutex = Mutex.new
        @extensions = [].freeze
        @hooks = Hooks.new
      end

      # Registers an extension.
      #
      # @param extension [Extension] an instance of {Extension} or a subclass of it
      # @return [Extension] the registered extension
      # @raise [ArgumentError] if the argument is not an {Extension} instance, or
      #   an extension with the same name is already registered. Existing
      #   registrations are left unchanged.
      def register(extension)
        return @registry.register(extension) if @registry

        unless extension.is_a?(Extension)
          raise ArgumentError, "job extension must be an instance of #{Extension}, got #{extension.inspect}"
        end

        @mutex.synchronize do
          if @extensions.any? { |registered| registered.name == extension.name }
            raise ArgumentError, "a job extension named #{extension.name.inspect} is already registered"
          end

          @extensions = (@extensions + [extension]).freeze
        end

        extension
      end

      def with_default(extension)
        unless extension.is_a?(Extension)
          raise ArgumentError, "default job extension must be an instance of #{Extension}, got #{extension.inspect}"
        end

        Registry.new(registry: self, default_extension: extension)
      end

      # Returns the extension that handles the given job.
      #
      # Extensions are asked through {Extension#handles?} in registration order,
      # and the first one that answers truthy is returned. An extension whose
      # {Extension#handles?} raises a StandardError is logged through the SDK
      # logger and skipped. Exceptions outside StandardError propagate.
      #
      # @param job [Object] the job, passed as-is to each extension
      # @return [Extension, nil] the earliest registered extension that handles
      #   the job, or nil if none does. With a default extension, returns that
      #   default when none handles the job
      def for(job)
        extension = @registry ? @registry.for(job) : @extensions.find { |candidate| handles?(candidate, job) }
        extension || @default_extension
      end

      # Calls a hook on an extension and returns its result, or the hook's
      # fallback result when the extension cannot supply valid data.
      #
      # The fallback result is returned when the extension is nil, when the hook
      # raises a StandardError, or when it returns data that does not match the
      # shape documented on the corresponding {Extension} method. Keys a Hash
      # result carries beyond those documented are dropped. Failures and
      # malformed results are logged through the SDK logger. Exceptions outside
      # StandardError propagate.
      #
      # Arguments are passed to the extension as given. Not mutating them is
      # the extension's obligation, documented on {Extension}.
      #
      # @example Applying an extension's scope data
      #   extension = Sentry.job_extensions.for(job)
      #   data = Sentry.job_extensions.call(extension, :scope_data, job: job)
      #   scope.set_contexts(data[:contexts]) if data[:contexts]
      #
      # @param extension [Extension, nil] the extension returned by {#for}
      # @param hook [Symbol] the name of a hook method documented on {Extension}
      # @param arguments [Array] the arguments documented on the hook's
      #   {Extension} method
      # @return [Object] the extension's result or the hook's fallback result
      # @raise [ArgumentError] if the hook is not a hook documented on {Extension}
      def call(extension, hook, **arguments)
        hooks = extension ? extension.hooks : @hooks
        fallback_result = hooks.fallback_result(hook, arguments)
        return fallback_result unless extension

        invoke(extension, hook, hooks, arguments, fallback_result)
      end

      # @!visibility private
      def clear
        return @registry.clear if @registry

        @mutex.synchronize { @extensions = [].freeze }
      end

      private

      def handles?(extension, job)
        extension.handles?(job)
      rescue StandardError => e
        log_error("Job extension #{extension.name.inspect} failed to check whether it handles a job", e)
        false
      end

      def invoke(extension, hook, hooks, arguments, fallback_result)
        result = extension.public_send(hook, **arguments)
        normalized = hooks.normalize(hook, result, arguments)
        return normalized unless normalized.equal?(Hooks::MALFORMED)

        log_warn("Job extension #{extension.name.inspect} returned malformed data from #{hook}: a #{result.class}")
        fallback_result
      rescue StandardError => e
        log_error("Job extension #{extension.name.inspect} failed in #{hook}", e)
        fallback_result
      end

      def sdk_logger
        Sentry.sdk_logger if Sentry.initialized?
      end
    end
  end
end
