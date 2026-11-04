# frozen_string_literal: true

require "sentry/rails/serializer"
require "sentry/rails/error_reporter_context"

module Sentry
  module Rails
    # The job extension sentry-rails uses for ActiveJob jobs. Backend gems
    # subclass it to enrich ActiveJob jobs run through their queue adapter, and
    # register it with {Sentry::Rails.register_active_job_extension}.
    class ActiveJobExtension < Sentry::JobExtensions::Extension
      include ErrorReporterContext

      SPAN_ORIGIN = "auto.queue.active_job"

      # @param serializer [#serialize] serializes job arguments for error events
      # @see Sentry::JobExtensions::Extension#initialize
      def initialize(name: :active_job, integration: Sentry::Rails, origin: SPAN_ORIGIN, serializer: Sentry::Rails::Serializer)
        super(name: name, integration: integration, origin: origin)
        @serializer = serializer
      end

      # Returns the name of the job class' queue adapter.
      #
      # @param job_class [Class]
      # @return [Symbol]
      def self.adapter_name(job_class)
        name = job_class.queue_adapter_name if job_class.respond_to?(:queue_adapter_name)
        (name || job_class.queue_adapter.class.name.demodulize.delete_suffix("Adapter").underscore).to_sym
      end

      # Returns the job's serialized payload carrying Sentry's trace propagation
      # headers and user data.
      #
      # @param job [ActiveJob::Base]
      # @param payload [Hash]
      # @return [Hash]
      def prepare_payload(job:, payload:)
        sentry_data = {}
        if Sentry.configuration.rails.active_job_propagate_traces
          headers = Sentry.get_trace_propagation_headers
          if headers && !headers.empty?
            sentry_data["trace_propagation_headers"] = headers
            payload = inject_trace_headers(job: job, payload: payload, headers: headers)
          end
        end

        if Sentry.configuration.data_collection.user_info
          user = Sentry.get_current_scope.user.transform_keys(&:to_s).slice(*ActiveJobExtensions::USER_FIELDS_ALLOWLIST)
          sentry_data["user"] = user unless user.empty?
        end

        sentry_data.empty? ? payload : payload.merge(ActiveJobExtensions::SENTRY_PAYLOAD_KEY => sentry_data)
      rescue StandardError => e
        Sentry.sdk_logger&.error("sentry-rails: failed to inject _sentry payload: #{e.class}: #{e.message}\n  #{Array(e.backtrace).first(5).join("\n  ")}")
        payload
      end

      # Enqueues the job even when recording its `queue.publish` span fails.
      #
      # @see Sentry::JobExtensions::Extension#instrument_enqueue
      def instrument_enqueue(job:, **context, &enqueue)
        enqueued = false
        super(job: job, **context) do
          enqueued = true
          enqueue.call
        end
      rescue StandardError => e
        raise if enqueued

        log_failure("record producer span", e)
        enqueue.call
      end

      # Also applies the user and ActiveJob context the job carries.
      #
      # @see Sentry::JobExtensions::Extension#start_job
      def start_job(scope:, job:, **context)
        user = job._sentry&.[]("user")
        scope.set_user(user.transform_keys(&:to_sym)) if user && !user.empty?
        scope.set_transaction_name(job.class.name, source: :task)

        super.tap { apply_active_job_context(scope, job) }
      end

      # Also adds the job's ActiveJob data to the event.
      #
      # @see Sentry::JobExtensions::Extension#capture_exception
      def capture_exception(job:, exception:, contexts: {}, tags: {}, extra: {}, **context)
        data = active_job_error_data(job)

        super(
          job: job,
          exception: exception,
          contexts: data[:contexts].merge(contexts),
          tags: data[:tags].merge(tags),
          extra: data[:extra].merge(extra),
          **context
        )
      end

      # Reads the trace propagation headers stored in the job's Sentry payload.
      #
      # @see Sentry::JobExtensions::Extension#extract_trace_headers
      def extract_trace_headers(job:, **)
        job._sentry&.[]("trace_propagation_headers") || {}
      end

      # Extends {#publish_messaging_data} with the job's receive latency and body size.
      #
      # @see Sentry::JobExtensions::Extension#messaging_data
      def messaging_data(job:, **context)
        data = publish_messaging_data(job: job, **context)
        data[:receive_latency] = Sentry::Utils::Latency.milliseconds_since(job.enqueued_at) if job.respond_to?(:enqueued_at)
        data[:body_size] = body_size(job._sentry_job_data) if Sentry.get_current_scope.get_span&.sampled
        data.compact
      end

      # Describes the job with its ActiveJob messaging attributes.
      #
      # @see Sentry::JobExtensions::Extension#publish_messaging_data
      def publish_messaging_data(job:, **)
        name = job.class.queue_adapter_name if job.class.respond_to?(:queue_adapter_name)
        {
          system: name.to_s.empty? ? "activejob" : name.to_s,
          message_id: job.job_id,
          destination: job.queue_name,
          retry_count: (job.executions.to_i if job.respond_to?(:executions))
        }.compact
      end

      # Follows `config.rails.active_job_report_on_retry_error`.
      #
      # @see Sentry::JobExtensions::Extension#report_retried_exception?
      def report_retried_exception?(job:, exception:, **)
        Sentry.configuration.rails.active_job_report_on_retry_error
      end

      private

      def log_failure(context, error)
        Sentry.sdk_logger&.error("sentry-rails: job extension #{name.inspect} failed to #{context}: #{error.class}: #{error.message}\n  #{Array(error.backtrace).first(5).join("\n  ")}")
      end

      def body_size(payload)
        JSON.generate(payload).bytesize if payload
      rescue StandardError
        nil
      end

      def apply_active_job_context(scope, job)
        required = {
          job_class: job.class.name,
          job_id: job.job_id,
          queue: job.queue_name,
          provider_job_id: job.provider_job_id
        }
        scope.set_contexts(active_job: scope.contexts.fetch(:active_job, {}).merge(required))
        scope.set_tags(queue: job.queue_name)
      end

      def active_job_error_data(job)
        queues = Sentry.configuration.data_collection.queues
        extra = {
          active_job: job.class.name,
          scheduled_at: job.scheduled_at,
          job_id: job.job_id,
          provider_job_id: job.provider_job_id,
          locale: job.locale
        }
        arguments = serialize_arguments(job.arguments) if queues
        extra[:arguments] = arguments unless arguments.nil?

        {
          contexts: queues ? execution_context : {},
          tags: { job_id: job.job_id, provider_job_id: job.provider_job_id },
          extra: extra
        }
      end

      def serialize_arguments(arguments)
        @serializer.serialize(arguments)
      rescue StandardError => e
        Sentry.sdk_logger&.error("sentry-rails: failed to serialize job arguments: #{e.class}: #{e.message}")
        nil
      end
    end
  end
end
