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

      def initialize
        @mutex = Mutex.new
        @extensions = [].freeze
      end

      # Registers an extension.
      #
      # @param extension [Extension] an instance of {Extension} or a subclass of it
      # @return [Extension] the registered extension
      # @raise [ArgumentError] if the argument is not an {Extension} instance, or
      #   an extension with the same name is already registered. Existing
      #   registrations are left unchanged.
      def register(extension)
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

      # Returns the extension that handles the given job.
      #
      # Extensions are asked through {Extension#handles?} in registration order,
      # and the first one that answers truthy is returned. An extension whose
      # {Extension#handles?} raises a StandardError is logged through the SDK
      # logger and skipped. Exceptions outside StandardError propagate.
      #
      # @param job [Object] the job, passed as-is to each extension
      # @return [Extension, nil] the earliest registered extension that handles
      #   the job, or nil if none does
      def for(job)
        @extensions.find { |extension| handles?(extension, job) }
      end

      # @!visibility private
      def clear
        @mutex.synchronize { @extensions = [].freeze }
      end

      private

      def handles?(extension, job)
        extension.handles?(job)
      rescue StandardError => e
        log_error("Job extension #{extension.name.inspect} failed to check whether it handles a job", e)
        false
      end

      def sdk_logger
        Sentry.sdk_logger if Sentry.initialized?
      end
    end
  end
end
