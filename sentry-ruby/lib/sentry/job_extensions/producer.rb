# frozen_string_literal: true

module Sentry
  module JobExtensions
    # @api private
    class Producer < Instrumentation
      OP_NAME = "queue.publish"

      attr_reader :origin

      def initialize(origin: nil, registry: Sentry.job_extensions)
        super(registry: registry)
        @origin = origin
      end

      def record_span(job, on_instrumentation_error: nil, **span_options, &enqueue)
        return with_span(job, **span_options, &enqueue) unless on_instrumentation_error

        enqueued = false
        run_enqueue = lambda do
          enqueued = true
          enqueue.call
        end

        begin
          with_span(job, **span_options, &run_enqueue)
        rescue StandardError => e
          raise if enqueued

          on_instrumentation_error.call(e)
          run_enqueue.call
        end
      end

      def prepare_payload(job, payload)
        payload
      end

      def inject_trace_headers(job, payload, headers)
        registry.call(registry.for(job), :inject_trace_headers, job: job, payload: payload, headers: headers)
      end

      private

      def with_span(job, description: nil, messaging_data: {}, default_messaging_data: {}, extension_messaging_keys: nil, retry_count: true, default_retry_count: nil)
        extension = registry.for(job)
        span_description = registry.call(extension, :publish_description, job: job) || description

        Sentry.with_child_span(op: OP_NAME, description: span_description) do |span|
          if span
            span_origin = registry.call(extension, :span_origin, job: job) || origin
            span.set_origin(span_origin) if span_origin

            set_messaging_data(span, resolve(default_messaging_data))
            extension_data = registry.call(extension, :publish_messaging_data, job: job)
            extension_data = extension_data.slice(*extension_messaging_keys) if extension_messaging_keys
            set_messaging_data(span, extension_data)
            set_messaging_data(span, resolve(messaging_data))
            set_retry_count(span, extension, job, default: resolve(default_retry_count)) if retry_count
          end

          yield
        end
      end
      class Delegated < Producer
        def record_span(job, **options)
          yield
        end
      end
    end
  end
end
