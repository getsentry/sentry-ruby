# frozen_string_literal: true

require "sentry/sidekiq/retry_policy"
require "sentry/sidekiq/failure_reporting"
require "sentry/sidekiq/context_filter"

module Sentry
  module Sidekiq
    # The job extension sentry-sidekiq uses for Sidekiq jobs, given as job Hashes.
    # Its retry and failure reporting follow sentry-sidekiq's configuration.
    #
    # @see ActiveJobSupport for how ActiveJob jobs on Sidekiq are reported
    class JobExtension < Sentry::JobExtensions::Extension
      SPAN_ORIGIN = "auto.queue.sidekiq"
      SIDEKIQ_NAME = "Sidekiq"
      MESSAGING_SYSTEM = "sidekiq"
      ENQUEUED_AT_IN_MILLISECONDS = ::Gem::Version.new(::Sidekiq::VERSION) >= ::Gem::Version.new("8.0.0")

      # @param retry_policy [RetryPolicy]
      # @param failure_reporting [FailureReporting]
      # @param serializer [#dump_json] encodes jobs to measure their body size
      # @see Sentry::JobExtensions::Extension#initialize
      def initialize(
        name: :sidekiq,
        integration: Sentry::Sidekiq,
        origin: SPAN_ORIGIN,
        retry_policy: RetryPolicy.build,
        failure_reporting: FailureReporting.new(retry_policy: retry_policy),
        serializer: ::Sidekiq
      )
        super(name: name, integration: integration, origin: origin)
        @retry_policy = retry_policy
        @failure_reporting = failure_reporting
        @serializer = serializer
      end

      # Returns the Sidekiq error context in the shape attached to error events.
      #
      # @param context [Hash]
      # @return [Hash]
      def error_context(context)
        without_arguments(ContextFilter.new(context).filtered)
      end

      # Adds the job as the `sidekiq` context, and its queue, jid, tags and user.
      #
      # @see Sentry::JobExtensions::Extension#scope_data
      def scope_data(job:, **)
        data = {
          contexts: { sidekiq: without_arguments(job) },
          tags: { queue: job["queue"], jid: job["jid"] }.merge(job_tags(job))
        }
        user = job["sentry_user"]
        data[:user] = user if user.is_a?(Hash)
        data
      end

      # Describes the Sidekiq message being processed.
      #
      # @see Sentry::JobExtensions::Extension#messaging_data
      def messaging_data(job:, **)
        data = {
          system: MESSAGING_SYSTEM,
          message_id: job["jid"],
          destination: job["queue"],
          receive_latency: receive_latency(job),
          retry_count: @retry_policy.retry_count(job) || 0
        }
        data[:body_size] = body_size(job) if Sentry.get_current_scope.get_span&.sampled
        data.compact
      end

      # Describes the Sidekiq message being enqueued.
      #
      # @see Sentry::JobExtensions::Extension#publish_messaging_data
      def publish_messaging_data(job:, **)
        { system: MESSAGING_SYSTEM, message_id: job["jid"], destination: job["queue"] }
      end

      # Follows the job's and Sidekiq's retry settings.
      #
      # @see Sentry::JobExtensions::Extension#will_retry?
      def will_retry?(job:, **)
        @retry_policy.will_retry?(job)
      end

      # Follows `config.sidekiq.report_after_job_retries`, `report_only_dead_jobs` and
      # the job's `attempt_threshold`.
      #
      # @see Sentry::JobExtensions::Extension#report_exception?
      def report_exception?(job:, exception:, sidekiq_config: nil, **)
        @failure_reporting.report?(job, sidekiq_config)
      end

      # Stores the headers in the job's `trace_propagation_headers`, unless it already has them.
      #
      # @see Sentry::JobExtensions::Extension#inject_trace_headers
      def inject_trace_headers(job:, payload:, headers:, **)
        return payload if payload["trace_propagation_headers"]

        payload.merge("trace_propagation_headers" => headers)
      end

      # Reads the job's `trace_propagation_headers`.
      #
      # @see Sentry::JobExtensions::Extension#extract_trace_headers
      def extract_trace_headers(job:, **)
        job["trace_propagation_headers"] || {}
      end

      # Names the transaction `Sidekiq/<job class>`.
      #
      # @see Sentry::JobExtensions::Extension#transaction_name
      def transaction_name(job:, **)
        name = job_class(job)
        name ? "#{SIDEKIQ_NAME}/#{name}" : SIDEKIQ_NAME
      end

      # Describes the `queue.publish` span with the job class.
      #
      # @see Sentry::JobExtensions::Extension#publish_description
      def publish_description(job:, **)
        job["class"].to_s
      end

      # Keeps the `queue.publish` span's default origin.
      #
      # @see Sentry::JobExtensions::Extension#publish_span_origin
      def publish_span_origin(job:, **)
        Span::DEFAULT_SPAN_ORIGIN
      end

      private

      def without_arguments(context)
        return context if Sentry.configuration.data_collection.queues

        context.each_with_object({}) do |(key, value), redacted|
          case key.to_s
          when "jobstr"
            next
          when "args"
            redacted[key] = active_job_payloads_without_arguments(value) if ActiveJobSupport.handles?(context)
          else
            redacted[key] = value
          end
        end
      end

      def active_job_payloads_without_arguments(args)
        Array(args).grep(Hash).map { |payload| payload.reject { |key, _value| key.to_s == "arguments" } }
      end

      def job_class(job)
        job["class"] if job.is_a?(Hash)
      end

      def job_tags(job)
        Array(job["tags"]).each_with_object({}) { |name, tags_hash| tags_hash[:"sidekiq.#{name}"] = true }
      end

      def body_size(job)
        @serializer.dump_json(job).bytesize
      rescue StandardError
        nil
      end

      def enqueued_at(job)
        enqueued_at = job["enqueued_at"]
        return unless enqueued_at

        ENQUEUED_AT_IN_MILLISECONDS ? Time.at(Rational(enqueued_at, 1000)) : Time.at(enqueued_at)
      end

      def receive_latency(job)
        Sentry::Utils::Latency.milliseconds_since(enqueued_at(job))&.round
      end
    end
  end
end
