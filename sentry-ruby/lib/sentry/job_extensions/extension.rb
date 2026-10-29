# frozen_string_literal: true

module Sentry
  module JobExtensions
    # Base class for objects that let a background-job backend enrich Sentry's
    # job integrations.
    #
    # A backend gem subclasses this class, receives everything the extension
    # depends on (configuration, collaborators) through its constructor, and
    # registers one instance with {Sentry.register_job_extension}. Sentry treats
    # jobs as opaque objects: only the extension interprets the job it is given.
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
      attr_reader :name, :hooks

      # @param name [String, Symbol] a non-empty name identifying the backend,
      #   stored as a frozen String
      # @raise [ArgumentError] if the name is not a non-empty String or Symbol
      def initialize(name:, validators: Validators.new)
        unless (name.is_a?(String) || name.is_a?(Symbol)) && !name.empty?
          raise ArgumentError, "job extension name must be a non-empty String or Symbol, got #{name.inspect}"
        end

        @name = name.to_s.dup.freeze
        @hooks = Hooks.new(validators: validators)
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

      # @!group Hooks
      #
      # Hooks are called by job integrations through {Registry#call}. Each hook maps its input to data
      # and must not mutate the objects it is given; the job integration
      # applies the returned data. Override only the hooks the backend can
      # supply: the defaults return the fallback result, which makes the
      # integration keep its own behavior. If a hook raises a StandardError or
      # returns data that does not match its documented shape, the failure is
      # logged through the SDK logger and the fallback result is used instead.
      # Hash keys beyond those documented for a hook are dropped.

      # Data to apply to the scope the job is performed in. Called before the
      # job is performed. A supplied user replaces the user the job
      # integration sets on the scope.
      #
      # @param job [Object] the job being performed
      # @return [Hash] a Hash with any of the keys +:contexts+ (a Hash of
      #   context name to Hash), +:tags+ (a Hash), +:extra+ (a Hash) and
      #   +:user+ (a Hash). The fallback result is an empty Hash.
      def scope_data(job:)
        {}
      end

      # Data to add to the event captured for an exception raised by the job.
      # Called when the job fails and its exception is about to be captured.
      #
      # Supplied tags and extra never replace a key already on the job's
      # scope. Each supplied context is merged into the scope's context of the
      # same name, keeping values already on the scope. Data the job integration captures
      # explicitly with the exception takes precedence over this data.
      #
      # @param job [Object] the job that failed
      # @param exception [Exception] the exception raised by the job
      # @return [Hash] a Hash with any of the keys +:contexts+ (a Hash of
      #   context name to Hash), +:tags+ (a Hash) and +:extra+ (a Hash).
      #   The fallback result is an empty Hash.
      def error_data(job:, exception:)
        {}
      end

      # The backend's own retry state for the job. Called when the job is
      # enqueued, before it is performed, and when it fails. Only +:count+ is
      # used when the job is enqueued or about to be performed; +:will_retry+
      # is used only when the job fails, to decide how the failure is
      # reported. The hook may be called several times for the same attempt,
      # so it must not change any state.
      #
      # @param job [Object] the job being enqueued, performed, or that failed
      # @return [Hash, nil] a Hash with both the keys +:count+ (a
      #   non-negative Integer, the number of retries already attempted) and
      #   +:will_retry+ (true or false, whether the backend will retry the
      #   failed attempt). The fallback result is nil, meaning the backend's
      #   retry state is unknown.
      def retry_info(job:)
        nil
      end

      # Whether the job integration captures the exception raised by the job.
      # Called when the job fails. Declining to capture does not change the
      # job's outcome: the job still fails and its transaction is still
      # finished as failed.
      #
      # @param job [Object] the job that failed
      # @param exception [Exception] the exception raised by the job
      # @return [Boolean, nil] true to capture the exception, false not to
      #   capture it. The fallback result is nil, which captures the exception
      #   only when the backend will not retry the job, as reported by
      #   +:will_retry+ from #retry_info.
      def report_exception?(job:, exception:)
        nil
      end

      # Whether the job integration captures an exception that the job
      # integration's own retry mechanism rescued and retries, so the backend
      # never sees it. Called when the job integration schedules the retry.
      #
      # @param job [Object] the job being retried
      # @param exception [Exception] the exception the job raised
      # @return [Boolean, nil] true to capture the exception, false not to
      #   capture it. The fallback result is nil, which keeps the job
      #   integration's own setting.
      def report_retried_exception?(job:, exception:)
        nil
      end

      # Adds trace propagation headers to the backend's job payload. Called
      # when a job is enqueued.
      #
      # @param payload [Object] the backend's job payload
      # @param headers [Hash{String => String}] the trace propagation headers
      #   to carry, such as +sentry-trace+ and +baggage+
      # @return [Object] a new payload of the same class as the one given,
      #   carrying the headers. The fallback result is the given payload,
      #   unchanged.
      def inject_trace_headers(job:, payload:, headers:)
        payload
      end

      # Reads the trace propagation headers carried by the backend's job
      # payload. Called before the job is performed, to continue the trace
      # started when it was enqueued. Only called when the job integration
      # has no trace headers of its own for the job.
      #
      # @param payload [Object] the backend's job payload
      # @return [Hash{String => String}, nil] the headers the payload carries.
      #   The job continues the trace they describe, and an empty Hash makes
      #   the job start a new trace. The fallback result is nil, which keeps
      #   the job integration's own trace handling.
      def extract_trace_headers(job:, payload:)
        nil
      end

      # Data for the messaging attributes of the producer span created when the
      # job is enqueued and the consumer span created when it is performed. On
      # the consumer span, supplied values replace the job integration's own;
      # on the producer span, they fill only attributes the job integration
      # does not set.
      #
      # @param job [Object] the job being enqueued or performed
      # @return [Hash] a Hash with any of the keys +:system+ (a String naming
      #   the backend), +:message_id+ (a String), +:destination+ (a String,
      #   such as the queue name), +:receive_latency+ (a Numeric, the
      #   milliseconds between enqueueing and the start of the job) and
      #   +:body_size+ (a non-negative Integer, the size of the message body
      #   in bytes). The fallback result is an empty Hash.
      def messaging_data(job:)
        {}
      end

      # The name of the transaction the job is performed in. Called before the
      # job is performed. Errors captured while the job runs carry the same
      # transaction name.
      #
      # @param job [Object] the job being performed
      # @return [String, nil] a non-empty String. The fallback result is nil,
      #   which keeps the name the job integration gives the transaction.
      def transaction_name(job:)
        nil
      end

      # The origin of the producer span created when the job is enqueued and
      # of the consumer transaction created when it is performed.
      #
      # @param job [Object] the job being enqueued or performed
      # @return [String, nil] a non-empty String, such as
      #   +"auto.queue.my_backend"+. The fallback result is nil, which keeps the
      #   job integration's own origin.
      def span_origin(job:)
        nil
      end

      # The description of the producer span created when the job is enqueued.
      #
      # @param job [Object] the job being enqueued
      # @return [String, nil] a non-empty String. The fallback result is nil,
      #   which keeps the description the job integration gives the span.
      def publish_description(job:)
        nil
      end

      # The integration the job's exceptions are captured under. Called when
      # the job fails and its exception is about to be captured. The
      # integration's name is recorded on the event and as its exception
      # mechanism.
      #
      # @param job [Object] the job that failed
      # @return [Sentry::Integrable, nil] an object extended with
      #   {Sentry::Integrable}, such as a registered integration module. The
      #   fallback result is nil, which keeps the job integration's own
      #   integration.
      def integration(job:)
        nil
      end

      def producer(job:)
        nil
      end

      def publish_messaging_data(job:)
        messaging_data(job: job)
      end

      # @!endgroup
    end
  end
end
