# frozen_string_literal: true

require "set"

module Sentry
  module Rails
    module ActiveJobExtensions
      SENTRY_PAYLOAD_KEY = "_sentry"

      USER_FIELDS_ALLOWLIST = %w[id email username].freeze

      def perform_now
        if !Sentry.initialized? || already_supported_by_sentry_integration?
          super
        else
          SentryReporter.record(
            self,
            trace_headers: @_sentry_trace_headers,
            user: @_sentry_user
          ) { super }
        end
      end

      def serialize
        payload = super
        return payload if !Sentry.initialized? || already_supported_by_sentry_integration?

        begin
          sentry_data = {}
          if Sentry.configuration.rails.active_job_propagate_traces
            headers = Sentry.get_trace_propagation_headers
            sentry_data["trace_propagation_headers"] = headers if headers && !headers.empty?
          end

          if Sentry.configuration.send_default_pii
            user = Sentry.get_current_scope.user || {}
            allowed = user.each_with_object({}) do |(k, v), acc|
              acc[k.to_s] = v if USER_FIELDS_ALLOWLIST.include?(k.to_s)
            end
            sentry_data["user"] = allowed unless allowed.empty?
          end

          payload[SENTRY_PAYLOAD_KEY] = sentry_data unless sentry_data.empty?
        rescue StandardError => e
          Sentry.sdk_logger&.error("sentry-rails: failed to inject _sentry payload: #{e}")
        end

        payload
      end

      def deserialize(job_data)
        super
        return if !Sentry.initialized? || already_supported_by_sentry_integration?

        begin
          sentry_data = job_data[SENTRY_PAYLOAD_KEY]
          return unless sentry_data

          @_sentry_trace_headers = sentry_data["trace_propagation_headers"]
          @_sentry_user = sentry_data["user"]
        rescue StandardError => e
          Sentry.sdk_logger&.error("sentry-rails: failed to extract _sentry payload: #{e}")
        end
      end

      def already_supported_by_sentry_integration?
        Sentry.configuration.rails.skippable_job_adapters.include?(self.class.queue_adapter.class.to_s)
      end

      class SentryReporter
        OP_NAME = "queue.active_job"
        SPAN_ORIGIN = "auto.queue.active_job"

        EVENT_HANDLERS = {
          "enqueue_retry.active_job" => :retry_handler
        }

        class << self
          def producer_callback_registered?
            @producer_callback_registered ||= false
          end

          def producer_callback_registered!
            @producer_callback_registered = true
          end

          def record_producer_span(job)
            return yield if !Sentry.initialized? || job.already_supported_by_sentry_integration?

            Sentry.with_child_span(op: "queue.publish", description: job.class.name) do |span|
              if span
                span.set_origin(SPAN_ORIGIN)
                span.set_data(Sentry::Span::DataConventions::MESSAGING_MESSAGE_ID, job.job_id)
                span.set_data(Sentry::Span::DataConventions::MESSAGING_DESTINATION_NAME, job.queue_name)
              end
              yield
            end
          end

          def record(job, trace_headers: nil, user: nil, &block)
            # Always give this thread a fresh hub cloned from the main hub so
            # the job's events are fully isolated.  Save and restore whatever
            # hub was on the thread before (e.g. the Rack request hub set by
            # CaptureExceptions, or a stale hub left by a recycled thread-pool
            # thread) so the outer context continues working correctly after
            # the job finishes.
            original_hub = Thread.current.thread_variable_get(Sentry::THREAD_LOCAL)
            Sentry.clone_hub_to_current_thread

            Sentry.with_scope do |scope|
              begin
                scope.set_user(user) if user && !user.empty?
                scope.set_transaction_name(job.class.name, source: :task)
                scope.set_tags(queue: job.queue_name)
                scope.set_contexts(active_job: {
                  job_class: job.class.name,
                  job_id: job.job_id,
                  queue: job.queue_name,
                  provider_job_id: job.provider_job_id
                })

                transaction_options = {
                  name: scope.transaction_name,
                  source: scope.transaction_source,
                  op: OP_NAME,
                  origin: SPAN_ORIGIN
                }

                transaction = if trace_headers && !trace_headers.empty?
                  continued = Sentry.continue_trace(trace_headers, **transaction_options)
                  Sentry.start_transaction(transaction: continued, **transaction_options)
                else
                  Sentry.start_transaction(**transaction_options)
                end

                if transaction
                  set_messaging_data(transaction, job)
                  scope.set_span(transaction)
                end

                yield.tap do
                  finish_sentry_transaction(transaction, 200)
                end
              rescue Exception => e # rubocop:disable Lint/RescueException
                finish_sentry_transaction(transaction, 500)

                capture_exception(job, e)

                raise
              end
            end
          ensure
            Thread.current.thread_variable_set(Sentry::THREAD_LOCAL, original_hub)
          end

          def set_messaging_data(transaction, job)
            transaction.set_data(Sentry::Span::DataConventions::MESSAGING_MESSAGE_ID, job.job_id)
            transaction.set_data(Sentry::Span::DataConventions::MESSAGING_DESTINATION_NAME, job.queue_name)
            transaction.set_data(Sentry::Span::DataConventions::MESSAGING_MESSAGE_RETRY_COUNT, [job.executions.to_i - 1, 0].max)

            if (latency = compute_latency(job))
              transaction.set_data(Sentry::Span::DataConventions::MESSAGING_MESSAGE_RECEIVE_LATENCY, latency)
            end
          end

          def compute_latency(job)
            return unless job.respond_to?(:enqueued_at) && job.enqueued_at

            enqueued_time = job.enqueued_at.is_a?(String) ? Time.parse(job.enqueued_at) : job.enqueued_at
            ((Time.now.to_f - enqueued_time.to_f) * 1000).round
          end

          def capture_exception(job, e)
            Sentry::Rails.capture_exception(
              e,
              extra: sentry_context(job),
              tags: {
                job_id: job.job_id,
                provider_job_id: job.provider_job_id
              }
            )
          end

          def register_event_handlers
            EVENT_HANDLERS.each do |name, handler|
              subscribers << ActiveSupport::Notifications.subscribe(name) do |*args|
                public_send(handler, *args)
              end
            end
          end

          def detach_event_handlers
            subscribers.each do |subscriber|
              ActiveSupport::Notifications.unsubscribe(subscriber)
            end
            subscribers.clear
          end

          # This handler does not capture error unless `active_job_report_on_retry_error` is true
          def retry_handler(*args)
            handle_error_event(*args) do |job, error|
              return if !Sentry.initialized? || job.already_supported_by_sentry_integration?
              return unless Sentry.configuration.rails.active_job_report_on_retry_error

              capture_exception(job, error)
            end
          end

          def handle_error_event(*args)
            event = ActiveSupport::Notifications::Event.new(*args)
            yield(event.payload[:job], event.payload[:error])
          end

          def finish_sentry_transaction(transaction, status)
            return unless transaction

            transaction.set_http_status(status)
            transaction.finish
          end

          def sentry_context(job)
            {
              active_job: job.class.name,
              arguments: sentry_serialize_arguments(job.arguments),
              scheduled_at: job.scheduled_at,
              job_id: job.job_id,
              provider_job_id: job.provider_job_id,
              locale: job.locale
            }
          end

          def sentry_serialize_arguments(argument)
            case argument
            when Range
              if (argument.begin || argument.end).is_a?(ActiveSupport::TimeWithZone)
                argument.to_s
              else
                argument.map { |v| sentry_serialize_arguments(v) }
              end
            when Hash
              argument.transform_values { |v| sentry_serialize_arguments(v) }
            when Array, Enumerable
              argument.map { |v| sentry_serialize_arguments(v) }
            when ->(v) { v.respond_to?(:to_global_id) }
              argument.to_global_id.to_s rescue argument
            else
              argument
            end
          end

          private

          def subscribers
            @__subscribers__ ||= Set.new
          end
        end
      end
    end
  end
end
