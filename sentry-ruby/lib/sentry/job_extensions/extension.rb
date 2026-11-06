# frozen_string_literal: true

module Sentry
  module JobExtensions
    # Base class for extensions that let a background-job backend enrich Sentry's
    # job integrations. A backend gem subclasses it and overrides the hooks it can
    # supply; jobs are opaque to Sentry and only interpreted by the extension.
    class Extension
      include LoggingHelper

      PUBLISH_OP = "queue.publish"
      PROCESS_OP = "queue.process"

      MESSAGING_DATA_ATTRIBUTES = {
        system: Span::DataConventions::MESSAGING_SYSTEM,
        message_id: Span::DataConventions::MESSAGING_MESSAGE_ID,
        destination: Span::DataConventions::MESSAGING_DESTINATION_NAME,
        receive_latency: Span::DataConventions::MESSAGING_MESSAGE_RECEIVE_LATENCY,
        retry_count: Span::DataConventions::MESSAGING_MESSAGE_RETRY_COUNT,
        body_size: Span::DataConventions::MESSAGING_MESSAGE_BODY_SIZE
      }.freeze

      EMPTY_HASH = {}.freeze
      private_constant :EMPTY_HASH

      EMPTY_ERROR_DATA = { contexts: {}.freeze, tags: {}.freeze, extra: {}.freeze }.freeze
      private_constant :EMPTY_ERROR_DATA

      # The extension's name, used in SDK log messages.
      # @return [Symbol]
      attr_reader :name

      # Creates an extension. Raises ArgumentError if the name is not a Symbol.
      #
      # @param name [Symbol]
      # @param integration [Module] the integration that captures the job's exceptions
      # @param origin [String] the origin of the job's spans
      def initialize(name:, integration:, origin:)
        raise ArgumentError, "job extension name must be a Symbol, got #{name.inspect}" unless name.is_a?(Symbol)

        @name = name
        @integration = integration
        @origin = origin
      end

      # Wraps enqueueing a job in a `queue.publish` span.
      #
      # @param job [Object]
      # @yieldreturn [Object] the result of enqueueing the job
      # @return [Object] the block's result
      def instrument_enqueue(job:, **context, &enqueue)
        return enqueue.call unless safely("decide whether to record the producer span", fallback: true) { record_publish_span?(job: job, **context) }

        Sentry.with_child_span(op: PUBLISH_OP) do |span|
          if span
            span.set_description(safely("describe the producer span") { publish_description(job: job, **context) })
            span.set_origin(safely("set the producer span origin", fallback: @origin) { publish_span_origin(job: job, **context) })
            set_messaging_data(span, hook_hash("collect the producer messaging data") { publish_messaging_data(job: job, **context) })
          end

          enqueue.call
        end
      end

      # Prepares the scope for performing the job and starts its `queue.process`
      # transaction, continuing the trace the job was enqueued in.
      #
      # @param scope [Scope]
      # @param job [Object]
      # @return [Transaction, nil]
      def start_job(scope:, job:, **context)
        apply_scope_data(scope, hook_hash("collect the scope data") { scope_data(job: job, **context) })

        job_name = safely("name the transaction") { transaction_name(job: job, **context) }
        scope.set_transaction_name(job_name, source: :task) if job_name

        trace_headers = hook_hash("extract trace headers") { extract_trace_headers(job: job, **context) }
        origin = safely("set the transaction origin", fallback: @origin) { span_origin(job: job, **context) }
        transaction = start_transaction(scope, trace_headers, origin)
        return unless transaction

        scope.set_span(transaction)
        set_messaging_data(transaction, hook_hash("collect the messaging data") { messaging_data(job: job, **context) })
        transaction
      end

      # Finishes the job's transaction with the given status.
      #
      # @param transaction [Transaction, nil]
      # @param status [Integer]
      # @return [void]
      def finish_job(transaction:, status:)
        return if !transaction || transaction.timestamp

        transaction.set_http_status(status)
        transaction.finish
      end

      # Captures an exception raised by the job, enriched with the extension's error data.
      #
      # @param job [Object]
      # @param exception [Exception]
      # @return [Event, nil]
      def capture_exception(job:, exception:, contexts: {}, tags: {}, extra: {}, **context)
        return unless Sentry.initialized?

        data = safely("collect the error data", fallback: EMPTY_ERROR_DATA) { normalized_error_data(error_data(job: job, exception: exception, **context)) }
        capturing_integration = safely("pick the capturing integration", fallback: @integration) { integration(job: job, **context) }

        capturing_integration.capture_exception(exception, **merged_error_data(data, contexts: contexts, tags: tags, extra: extra))
      end

      # Runs a hook, logging its failure and returning `fallback` instead of raising.
      #
      # @param context [String] what the hook does, used in the log message
      # @return [Object]
      def safely(context, fallback: nil)
        yield
      rescue StandardError => e
        log_failure(context, e)
        fallback
      end

      ##### Hooks #####
      #
      # Called by job integrations with the job and any extra keyword context.
      # Hooks must not mutate the objects they are given.

      # Returns whether to record a `queue.publish` span when the job is enqueued.
      #
      # @param job [Object]
      # @return [Boolean]
      def record_publish_span?(job:, **)
        true
      end

      # Returns data to apply to the scope the job is performed in.
      #
      # @param job [Object]
      # @return [Hash] with optional `:contexts`, `:tags`, `:extra` and `:user`
      def scope_data(job:, **)
        {}
      end

      # Returns data to add to the event captured for a failed job. Data already on
      # the scope or passed explicitly by the job integration takes precedence.
      #
      # @param job [Object]
      # @param exception [Exception]
      # @return [Hash] with optional `:contexts`, `:tags` and `:extra`
      def error_data(job:, exception:, **)
        {}
      end

      # Returns whether the backend will retry the failed job.
      #
      # @param job [Object]
      # @return [Boolean]
      def will_retry?(job:, **)
        false
      end

      # Returns whether to capture the job's exception. By default only when the
      # backend won't retry the job.
      #
      # @param job [Object]
      # @param exception [Exception]
      # @return [Boolean]
      def report_exception?(job:, exception:, **context)
        !will_retry?(job: job, exception: exception, **context)
      end

      # Returns whether to capture an exception that the job integration's own
      # retry mechanism retries, so the backend never sees it.
      #
      # @param job [Object]
      # @param exception [Exception]
      # @return [Boolean]
      def report_retried_exception?(job:, exception:, **)
        false
      end

      # Returns the backend's job payload carrying the trace propagation headers.
      #
      # @param job [Object]
      # @param payload [Object]
      # @param headers [Hash{String => String}]
      # @return [Object] a payload of the same class as the one given
      def inject_trace_headers(job:, payload:, headers:, **)
        payload
      end

      # Returns the trace propagation headers the job carries, so that performing
      # it continues the trace it was enqueued in.
      #
      # @param job [Object]
      # @return [Hash{String => String}]
      def extract_trace_headers(job:, **)
        {}
      end

      # Returns messaging attributes for the job's spans.
      #
      # @param job [Object]
      # @return [Hash] with optional `:system`, `:message_id`, `:destination`,
      #   `:receive_latency`, `:retry_count` and `:body_size`
      def messaging_data(job:, **)
        {}
      end

      # Returns messaging attributes for the `queue.publish` span. Defaults to
      # {#messaging_data}.
      #
      # @param job [Object]
      # @return [Hash]
      def publish_messaging_data(job:, **context)
        messaging_data(job: job, **context)
      end

      # Returns the name of the job's transaction. Defaults to the job's class name.
      #
      # @param job [Object]
      # @return [String, nil]
      def transaction_name(job:, **)
        job.class.name
      end

      # Returns the description of the `queue.publish` span. Defaults to the job's class name.
      #
      # @param job [Object]
      # @return [String, nil]
      def publish_description(job:, **)
        job.class.name
      end

      # Returns the origin of the job's transaction. Defaults to the extension's origin.
      #
      # @param job [Object]
      # @return [String]
      def span_origin(job:, **)
        @origin
      end

      # Returns the origin of the `queue.publish` span. Defaults to {#span_origin}.
      #
      # @param job [Object]
      # @return [String]
      def publish_span_origin(job:, **context)
        span_origin(job: job, **context)
      end

      # Returns the integration that captures the job's exceptions. Defaults to
      # the extension's integration.
      #
      # @param job [Object]
      # @return [Module]
      def integration(job:, **)
        @integration
      end

      private

      def hook_hash(description)
        safely(description, fallback: EMPTY_HASH) do
          value = yield
          value.nil? ? EMPTY_HASH : Hash(value)
        end
      end

      def start_transaction(scope, trace_headers, origin)
        options = {
          name: scope.transaction_name,
          source: scope.transaction_source,
          op: PROCESS_OP,
          origin: origin
        }

        if trace_headers.empty?
          Sentry.start_transaction(**options)
        else
          Sentry.start_transaction(transaction: Sentry.continue_trace(trace_headers, **options), **options)
        end
      end

      def apply_scope_data(scope, data)
        scope.set_contexts(data[:contexts]) if data[:contexts]
        scope.set_tags(data[:tags]) if data[:tags]
        scope.set_extras(data[:extra]) if data[:extra]
        scope.set_user(data[:user]) if data[:user]
      end

      def set_messaging_data(span, data)
        MESSAGING_DATA_ATTRIBUTES.each do |key, attribute|
          span.set_data(attribute, data[key]) if data.key?(key)
        end
      end

      def normalized_error_data(data)
        data = Hash(data)

        {
          contexts: Hash(data[:contexts]).transform_values { |context| Hash(context) },
          tags: Hash(data[:tags]),
          extra: Hash(data[:extra])
        }
      end

      # Builds the capture options so that the caller's contexts, tags and extra
      # take precedence over the scope's, and the scope's over the extension's.
      #
      # Every value passed to capture_exception becomes event data, and
      # Scope#apply_to_event lets event data beat scope data. It also merges
      # contexts by name, so an event context replaces the scope context of the
      # same name entirely. The extension's tags and extra therefore leave out
      # keys the scope already has, and each extension context absorbs the scope
      # context of the same name before the caller's values are merged on top.
      def merged_error_data(data, contexts:, tags:, extra:)
        scope = Sentry.get_current_scope

        merged_contexts = contexts_with_scope_values(data[:contexts], scope.contexts).merge(contexts)
        options = {
          extra: without_scope_keys(data[:extra], scope.extra).merge(extra),
          tags: without_scope_keys(data[:tags], scope.tags).merge(tags),
          hint: { background: false }
        }
        options[:contexts] = merged_contexts unless merged_contexts.empty?
        options
      end

      def without_scope_keys(values, scope_values)
        values.reject { |key, _value| scope_values.key?(key) }
      end

      def contexts_with_scope_values(contexts, scope_contexts)
        contexts.to_h { |name, context| [name, context.merge(scope_contexts.fetch(name, {}))] }
      end

      def log_failure(context, error)
        log_error("Job extension #{name.inspect} failed to #{context}", error)
      end

      def sdk_logger
        Sentry.sdk_logger if Sentry.initialized?
      end
    end
  end
end
