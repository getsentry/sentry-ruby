# frozen_string_literal: true

module Sentry
  module JobExtensions
    # Base class for objects that let a background-job backend enrich Sentry's
    # job integrations.
    #
    # A backend gem subclasses this class, receives everything the extension
    # depends on (configuration, collaborators) through its constructor, and
    # registers one instance with {Sentry.register_job_extension}. Sentry never
    # instantiates extensions itself and treats jobs as opaque objects: only the
    # extension interprets the job it is given.
    #
    # @example Defining and registering an extension
    #   class MyBackend::SentryJobExtension < Sentry::JobExtensions::Extension
    #     def initialize(config:)
    #       super(name: "my_backend")
    #       @config = config
    #     end
    #
    #     def handles?(job)
    #       job.class.queue_adapter_name.to_s == "my_backend"
    #     end
    #   end
    #
    #   Sentry.register_job_extension(MyBackend::SentryJobExtension.new(config: MyBackend.config))
    class Extension
      # The extension's unique name. No two registered extensions can share it.
      #
      # @return [String]
      attr_reader :name

      # @param name [String, Symbol] a non-empty name identifying the backend,
      #   stored as a frozen String
      # @raise [ArgumentError] if the name is not a non-empty String or Symbol
      def initialize(name:)
        unless (name.is_a?(String) || name.is_a?(Symbol)) && !name.empty?
          raise ArgumentError, "job extension name must be a non-empty String or Symbol, got #{name.inspect}"
        end

        @name = name.to_s.dup.freeze
      end

      # Whether this extension handles the given job. Override it to claim
      # the jobs run by the extension's backend.
      #
      # If this method raises a StandardError, the failure is logged through the
      # SDK logger and the extension is treated as not handling the job.
      #
      # @param job [Object] the job, as passed by the job integration
      # @return [Boolean] false unless overridden
      def handles?(job)
        false
      end
    end
  end
end
