# frozen_string_literal: true

require "sentry/sidekiq/context_filter"
require "sentry/sidekiq/retry_policy"

module Sentry
  module Sidekiq
    class JobExtension < Sentry::JobExtensions::Extension
      SIDEKIQ_NAME = "Sidekiq"
      WITH_SIDEKIQ_8 = ::Gem::Version.new(::Sidekiq::VERSION) >= ::Gem::Version.new("8.0.0")

      def initialize(retry_policy: RetryPolicy.build)
        super(name: "sidekiq")
        @retry_policy = retry_policy
      end

      def handles?(job)
        job.is_a?(Hash) && job.key?("jid")
      end

      def scope_data(job:)
        sidekiq_job = job
        return {} unless sidekiq_job

        data = {
          contexts: { sidekiq: ContextFilter.new(sidekiq_job).filtered },
          tags: { queue: sidekiq_job["queue"], jid: sidekiq_job["jid"] }.merge(job_tags(sidekiq_job))
        }
        user = sidekiq_job["sentry_user"]
        data[:user] = user if user.is_a?(Hash)
        data
      end

      def messaging_data(job:)
        {
          message_id: job["jid"],
          destination: job["queue"],
          receive_latency: receive_latency(job)
        }.compact
      end

      def retry_info(job:)
        { count: @retry_policy.retry_count(job) || 0, will_retry: @retry_policy.will_retry?(job) }
      end

      def inject_trace_headers(job:, payload:, headers:)
        return payload if payload["trace_propagation_headers"]

        payload.merge("trace_propagation_headers" => headers)
      end

      def extract_trace_headers(job:, payload:)
        payload["trace_propagation_headers"]
      end

      def transaction_name(job:)
        name = job_class(job)
        "#{SIDEKIQ_NAME}/#{name}" if name
      end

      def error_context_transaction_name(context)
        job = context["wrapped"] || context["class"] ? context : context[:job]
        return transaction_name(job: job) if job_class(job)

        context[:event] ? "#{SIDEKIQ_NAME}/#{context[:event]}" : SIDEKIQ_NAME
      end

      private

      def job_class(job)
        job["wrapped"] || job["class"] if job.is_a?(Hash)
      end


      def job_tags(job)
        Array(job["tags"]).each_with_object({}) { |name, tags_hash| tags_hash[:"sidekiq.#{name}"] = true }
      end

      if WITH_SIDEKIQ_8
        def receive_latency(job)
          now_in_ms - job["enqueued_at"] if job["enqueued_at"]
        end
      else
        def receive_latency(job)
          ((Time.now.to_f - job["enqueued_at"]) * 1000).round if job["enqueued_at"]
        end
      end

      def now_in_ms
        ::Process.clock_gettime(::Process::CLOCK_REALTIME, :millisecond)
      end
    end
  end
end
