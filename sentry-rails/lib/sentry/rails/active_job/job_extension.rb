# frozen_string_literal: true

require "sentry/rails/serializer"
require "sentry/rails/error_reporter_context"

module Sentry
  module Rails
    module ActiveJobExtensions
      class JobExtension < Sentry::JobExtensions::Extension
        include ErrorReporterContext

        SPAN_ORIGIN = "auto.queue.active_job"
        USER_FIELDS_ALLOWLIST = %w[id email username].freeze

        attr_reader :registry

        def initialize
          super(name: "active_job")
          @registry = Sentry.job_extensions.with_default(self)
        end

        def merge_hook(hook, default:, override:)
          case hook
          when :scope_data
            contexts = override.fetch(:contexts, {}).merge(default[:contexts]) { |_name, backend, generic| backend.merge(generic) }
            override.merge(contexts: contexts, tags: override.fetch(:tags, {}).merge(default[:tags]))
          when :messaging_data
            default.merge(override)
          when :publish_messaging_data
            override.merge(default)
          when :error_data, :inject_trace_headers
            override
          else
            super
          end
        end

        def handles?(job)
          job.is_a?(::ActiveJob::Base)
        end

        def producer(job:)
          @producer ||= Producer.new(registry: registry, origin: SPAN_ORIGIN)
        end

        def scope_data(job:)
          {
            contexts: { active_job: {
              job_class: job.class.name,
              job_id: job.job_id,
              queue: job.queue_name,
              provider_job_id: job.provider_job_id
            } },
            tags: { queue: job._sentry&.[]("delivery_queue") || job.queue_name }
          }
        end

        def error_data(job:, exception:)
          extra = {
            active_job: job.class.name,
            scheduled_at: job.scheduled_at,
            job_id: job.job_id,
            provider_job_id: job.provider_job_id,
            locale: job.locale
          }
          extra[:arguments] = Sentry::Rails::Serializer.serialize(job.arguments) if Sentry.configuration.data_collection.queues

          {
            contexts: Sentry.configuration.data_collection.queues ? execution_context : {},
            tags: { job_id: job.job_id, provider_job_id: job.provider_job_id },
            extra: extra
          }
        end

        def messaging_data(job:)
          data = publish_messaging_data(job: job)
          data[:receive_latency] = Sentry::Utils::Latency.milliseconds_since(job.enqueued_at) if job.respond_to?(:enqueued_at)
          data[:body_size] = body_size(job._sentry_job_data)
          data.compact
        end

        def body_size(payload)
          JSON.generate(payload).bytesize if payload
        rescue StandardError
          nil
        end

        def publish_messaging_data(job:)
          name = job.class.queue_adapter_name if job.class.respond_to?(:queue_adapter_name)
          {
            system: name.to_s.empty? ? "activejob" : name.to_s,
            message_id: job.job_id,
            destination: job.queue_name
          }
        end

        def retry_info(job:)
          { count: job.executions.to_i, will_retry: false }
        end

        def report_retried_exception?(job:, exception:)
          Sentry.configuration.rails.active_job_report_on_retry_error
        end

        def transaction_name(job:)
          job.class.name
        end

        def publish_description(job:)
          job.class.name
        end

        def span_origin(job:)
          SPAN_ORIGIN
        end

        def integration(job:)
          Sentry::Rails
        end
      end
    end
  end
end
