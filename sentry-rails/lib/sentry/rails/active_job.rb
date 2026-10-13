# frozen_string_literal: true

require "set"
require "sentry/rails/serializer"
require "sentry/rails/error_reporter_context"

module Sentry
  module Rails
    module ActiveJobExtensions
      SENTRY_PAYLOAD_KEY = "_sentry"

      USER_FIELDS_ALLOWLIST = %w[id email username].freeze

      def self.prepended(base)
        base.attr_accessor :_sentry
        base.attr_reader :_sentry_job_data
      end

      def perform_now
        if !Sentry.initialized? || already_supported_by_sentry_integration?
          super
        else
          data = _sentry || {}
          SentryReporter.record(
            self,
            trace_headers: data["trace_propagation_headers"],
            user: data["user"],
            payload: _sentry_job_data
          ) { super }
        end
      end

      def serialize
        payload = super
        return payload if !Sentry.initialized? || already_supported_by_sentry_integration?
        return payload if SentryReporter.producer.instrumented_by_extension?(self)

        begin
          sentry_data = {}
          if Sentry.configuration.rails.active_job_propagate_traces
            headers = Sentry.get_trace_propagation_headers
            if headers && !headers.empty?
              sentry_data["trace_propagation_headers"] = headers
              payload = SentryReporter.producer.inject_trace_headers(self, payload, headers)
            end
          end

          if Sentry.configuration.data_collection.user_info
            user = Sentry.get_current_scope.user
            allowed = user.transform_keys(&:to_s).slice(*USER_FIELDS_ALLOWLIST)
            sentry_data["user"] = allowed unless allowed.empty?
          end

          payload[SENTRY_PAYLOAD_KEY] = sentry_data unless sentry_data.empty?
        rescue StandardError => e
          Sentry.sdk_logger&.error("sentry-rails: failed to inject _sentry payload: #{e.class}: #{e.message}\n  #{Array(e.backtrace).first(5).join("\n  ")}")
        end

        payload
      end

      def deserialize(job_data)
        super
        return if !Sentry.initialized? || already_supported_by_sentry_integration?

        begin
          @_sentry_job_data = job_data
          self._sentry = job_data[SENTRY_PAYLOAD_KEY]
        rescue StandardError => e
          Sentry.sdk_logger&.error("sentry-rails: failed to extract _sentry payload: #{e.class}: #{e.message}\n  #{Array(e.backtrace).first(5).join("\n  ")}")
        end
      end

      def already_supported_by_sentry_integration?
        !Sentry::Rails.active_job_owns_adapter?(self.class.queue_adapter.class)
      end

      class SentryReporter
        SPAN_ORIGIN = "auto.queue.active_job"

        # Emitted as messaging.system when the configured queue adapter's
        # identity cannot be resolved from the job. ActiveJob is adapter-agnostic
        # and supports arbitrary third-party backends, so the concrete value is
        # normally derived from the adapter itself; this is only the last resort.
        MESSAGING_SYSTEM_FALLBACK = "activejob"

        EVENT_HANDLERS = {
          "enqueue_retry.active_job" => :retry_handler
        }

        class << self
          include ErrorReporterContext

          def consumer
            @consumer ||= Sentry::JobExtensions::Consumer.new(integration: Sentry::Rails, origin: SPAN_ORIGIN)
          end

          def producer
            @producer ||= Sentry::JobExtensions::Producer.new(origin: SPAN_ORIGIN)
          end

          def job_extensions
            @job_extensions ||= Sentry.job_extensions
          end

          def call_hook(job, hook, **arguments)
            job_extensions.call(job_extensions.for(job), hook, job: job, **arguments)
          end

          def producer_callback_registered?
            @producer_callback_registered ||= false
          end

          def producer_callback_registered!
            @producer_callback_registered = true
          end

          def record_producer_span(job, &enqueue)
            return yield if !Sentry.initialized? || job.already_supported_by_sentry_integration?
            return yield if producer.instrumented_by_extension?(job)

            producer.record_span(
              job,
              description: job.class.name,
              messaging_data: -> {
                {
                  system: messaging_system(job),
                  message_id: job.job_id,
                  destination: job.queue_name
                }.compact
              },
              default_retry_count: -> { executions(job) },
              on_instrumentation_error: method(:log_producer_span_error),
              &enqueue
            )
          end

          def log_producer_span_error(e)
            Sentry.sdk_logger&.error("sentry-rails: failed to record producer span: #{e.class}: #{e.message}\n  #{Array(e.backtrace).first(5).join("\n  ")}")
          end

          def record(job, trace_headers: nil, user: nil, payload: nil, &block)
            original_hub = Sentry.get_current_hub_internal
            Sentry.clone_hub_to_current_thread

            Sentry.with_scope do |scope|
              begin
                scope.set_user(user.transform_keys(&:to_sym)) if user && !user.empty?

                consumer.apply_scope_data(scope, job)

                scope.set_transaction_name(consumer.transaction_name(job) || job.class.name, source: :task)
                scope.set_tags(queue: job.queue_name)

                scope.set_contexts(active_job: {
                  job_class: job.class.name,
                  job_id: job.job_id,
                  queue: job.queue_name,
                  provider_job_id: job.provider_job_id
                })

                transaction = consumer.start_transaction(
                  scope, job,
                  trace_headers: trace_headers,
                  payload: payload,
                  messaging_data: -> {
                    {
                      system: messaging_system(job),
                      message_id: job.job_id,
                      destination: job.queue_name,
                      receive_latency: compute_latency(job)
                    }
                  },
                  default_retry_count: executions(job)
                )

                yield.tap do
                  consumer.finish_transaction(transaction, 200)
                end
              rescue Exception => e # rubocop:disable Lint/RescueException
                consumer.finish_transaction(transaction, 500)

                capture_exception(job, e) if consumer.report_exception?(job, e)

                raise
              end
            end
          ensure
            Sentry.set_current_hub_internal(original_hub)
          end

          def messaging_system(job)
            name = job.class.queue_adapter_name if job.class.respond_to?(:queue_adapter_name)
            name = name.to_s
            name.empty? ? MESSAGING_SYSTEM_FALLBACK : name
          end

          # Number of retries the job has already gone through, as observed at
          # the moment the span is opened. On the consumer the span opens before
          # ActiveJob increments +executions+, so a job's first attempt reads 0,
          # its first retry reads 1, and so on. On the producer the retry enqueue
          # runs after the failed attempt bumped +executions+, so it observes the
          # same progression.
          def executions(job)
            job.executions.to_i if job.respond_to?(:executions)
          end

          def compute_latency(job)
            return unless job.respond_to?(:enqueued_at) && job.enqueued_at

            enqueued_time = job.enqueued_at.is_a?(String) ? Time.parse(job.enqueued_at) : job.enqueued_at
            (Time.now.to_f - enqueued_time.to_f) * 1000.0
          end

          def capture_exception(job, e)
            consumer.capture_exception(
              job, e,
              contexts: Sentry.configuration.data_collection.queues ? execution_context : {},
              tags: { job_id: job.job_id, provider_job_id: job.provider_job_id },
              extra: sentry_context(job)
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
              return if error.nil?
              return if !Sentry.initialized? || job.already_supported_by_sentry_integration?
              return unless consumer.report_retried_exception?(job, error, default: Sentry.configuration.rails.active_job_report_on_retry_error)

              capture_exception(job, error)
            end
          end

          def handle_error_event(*args)
            event = ActiveSupport::Notifications::Event.new(*args)
            yield(event.payload[:job], event.payload[:error])
          end

          def sentry_context(job)
            context = {
              active_job: job.class.name,
              scheduled_at: job.scheduled_at,
              job_id: job.job_id,
              provider_job_id: job.provider_job_id,
              locale: job.locale
            }

            if Sentry.configuration.data_collection.queues
              context[:arguments] = sentry_serialize_arguments(job.arguments)
            end

            context
          end

          def sentry_serialize_arguments(argument)
            Sentry::Rails::Serializer.serialize(argument)
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
