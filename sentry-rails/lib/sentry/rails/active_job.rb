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
        return payload if SentryReporter.instrumented_by_extension?(self)

        begin
          sentry_data = {}
          if Sentry.configuration.rails.active_job_propagate_traces
            headers = Sentry.get_trace_propagation_headers
            if headers && !headers.empty?
              sentry_data["trace_propagation_headers"] = headers
              payload = SentryReporter.call_hook(self, :inject_trace_headers, payload: payload, headers: headers)
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
        OP_NAME = "queue.process"
        SPAN_ORIGIN = "auto.queue.active_job"

        # Emitted as messaging.system when the configured queue adapter's
        # identity cannot be resolved from the job. ActiveJob is adapter-agnostic
        # and supports arbitrary third-party backends, so the concrete value is
        # normally derived from the adapter itself; this is only the last resort.
        MESSAGING_SYSTEM_FALLBACK = "activejob"

        MESSAGING_DATA_ATTRIBUTES = {
          system: Sentry::Span::DataConventions::MESSAGING_SYSTEM,
          message_id: Sentry::Span::DataConventions::MESSAGING_MESSAGE_ID,
          destination: Sentry::Span::DataConventions::MESSAGING_DESTINATION_NAME,
          receive_latency: Sentry::Span::DataConventions::MESSAGING_MESSAGE_RECEIVE_LATENCY
        }.freeze

        EVENT_HANDLERS = {
          "enqueue_retry.active_job" => :retry_handler
        }

        class << self
          include ErrorReporterContext

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

          def instrumented_by_extension?(job)
            call_hook(job, :instruments_enqueue?) == true
          end

          def record_producer_span(job, &enqueue)
            return yield if !Sentry.initialized? || job.already_supported_by_sentry_integration?

            return yield if instrumented_by_extension?(job)

            enqueued = false

            run_enqueue = lambda do
              enqueued = true
              enqueue.call
            end

            begin
              description = call_hook(job, :publish_description) || job.class.name
              Sentry.with_child_span(op: "queue.publish", description: description) do |span|
                if span
                  span.set_origin(call_hook(job, :span_origin) || SPAN_ORIGIN)
                  set_extension_messaging_data(span, job)
                  span.set_data(Sentry::Span::DataConventions::MESSAGING_SYSTEM, messaging_system(job))
                  span.set_data(Sentry::Span::DataConventions::MESSAGING_MESSAGE_ID, job.job_id)
                  span.set_data(Sentry::Span::DataConventions::MESSAGING_DESTINATION_NAME, job.queue_name)

                  if (count = retry_count(job))
                    span.set_data(Sentry::Span::DataConventions::MESSAGING_MESSAGE_RETRY_COUNT, count)
                  end
                end

                run_enqueue.call
              end
            rescue StandardError => e
              raise if enqueued

              log_producer_span_error(e)

              run_enqueue.call
            end
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

                apply_extension_scope_data(scope, job)

                scope.set_transaction_name(call_hook(job, :transaction_name) || job.class.name, source: :task)
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
                  origin: call_hook(job, :span_origin) || SPAN_ORIGIN
                }

                extracted_trace = false
                if (trace_headers.nil? || trace_headers.empty?) && payload
                  extracted_headers = call_hook(job, :extract_trace_headers, payload: payload)
                  unless extracted_headers.nil?
                    trace_headers = extracted_headers
                    extracted_trace = true
                  end
                end

                transaction = if extracted_trace || (trace_headers && !trace_headers.empty?)
                  continued = Sentry.continue_trace(trace_headers, **transaction_options)
                  Sentry.start_transaction(transaction: continued, **transaction_options)
                else
                  Sentry.start_transaction(**transaction_options)
                end

                if transaction
                  set_messaging_data(transaction, job)
                  set_extension_messaging_data(transaction, job)
                  scope.set_span(transaction)
                end

                yield.tap do
                  finish_sentry_transaction(transaction, 200)
                end
              rescue Exception => e # rubocop:disable Lint/RescueException
                finish_sentry_transaction(transaction, 500)

                capture_exception(job, e) if report_exception?(job, e)

                raise
              end
            end
          ensure
            Sentry.set_current_hub_internal(original_hub)
          end

          def set_messaging_data(transaction, job)
            transaction.set_data(Sentry::Span::DataConventions::MESSAGING_SYSTEM, messaging_system(job))
            transaction.set_data(Sentry::Span::DataConventions::MESSAGING_MESSAGE_ID, job.job_id)
            transaction.set_data(Sentry::Span::DataConventions::MESSAGING_DESTINATION_NAME, job.queue_name)
            if (count = retry_count(job))
              transaction.set_data(Sentry::Span::DataConventions::MESSAGING_MESSAGE_RETRY_COUNT, count)
            end

            if (latency = compute_latency(job))
              transaction.set_data(Sentry::Span::DataConventions::MESSAGING_MESSAGE_RECEIVE_LATENCY, latency)
            end
          end

          def apply_extension_scope_data(scope, job)
            data = call_hook(job, :scope_data)
            scope.set_contexts(data[:contexts]) if data[:contexts]
            scope.set_tags(data[:tags]) if data[:tags]
            scope.set_extras(data[:extra]) if data[:extra]
            scope.set_user(data[:user]) if data[:user]
          end

          def set_extension_messaging_data(span, job)
            call_hook(job, :messaging_data).each do |key, value|
              span.set_data(MESSAGING_DATA_ATTRIBUTES.fetch(key), value)
            end
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
          def retry_count(job)
            if (info = call_hook(job, :retry_info))
              info[:count]
            elsif job.respond_to?(:executions)
              job.executions.to_i
            end
          end

          def backend_will_retry?(job)
            info = call_hook(job, :retry_info)
            info ? info[:will_retry] : false
          end

          def report_exception?(job, exception)
            decision = call_hook(job, :report_exception?, exception: exception)
            decision.nil? ? !backend_will_retry?(job) : decision
          end

          def report_retried_exception?(job, exception)
            decision = call_hook(job, :report_retried_exception?, exception: exception)
            decision.nil? ? Sentry.configuration.rails.active_job_report_on_retry_error : decision
          end

          def compute_latency(job)
            return unless job.respond_to?(:enqueued_at) && job.enqueued_at

            enqueued_time = job.enqueued_at.is_a?(String) ? Time.parse(job.enqueued_at) : job.enqueued_at
            (Time.now.to_f - enqueued_time.to_f) * 1000.0
          end

          def capture_exception(job, e)
            error_data = additive_error_data(
              call_hook(job, :error_data, exception: e)
            )

            options = {
              extra: error_data[:extra].merge(sentry_context(job)),
              tags: error_data[:tags].merge(
                job_id: job.job_id,
                provider_job_id: job.provider_job_id
              ),
              # Send synchronously: a worker process may exit before the async
              # background worker flushes its queue, which would drop the event.
              hint: { background: false }
            }

            contexts = error_data[:contexts]
            contexts = contexts.merge(matching_keys(execution_context, contexts)) if Sentry.configuration.data_collection.queues
            options[:contexts] = contexts if Sentry.configuration.data_collection.queues || !contexts.empty?

            integration = call_hook(job, :integration) || Sentry::Rails
            integration.capture_exception(e, **options)
          end

          def additive_error_data(data)
            scope = Sentry.get_current_scope

            {
              contexts: matching_keys(data.fetch(:contexts, {}), scope.contexts).to_h do |name, context|
                scope_context = scope.contexts.fetch(name, {})
                context = matching_keys(context, scope_context)
                [name, context.merge(scope_context)]
              end,
              tags: matching_keys(data.fetch(:tags, {}), scope.tags).reject { |key, _value| scope.tags.key?(key) },
              extra: matching_keys(data.fetch(:extra, {}), scope.extra).reject { |key, _value| scope.extra.key?(key) }
            }
          end

          def matching_keys(data, reference)
            keys = reference.keys.to_h { |key| [key.to_s, key] }
            data.transform_keys { |key| keys.fetch(key.to_s, key) }
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
              return unless report_retried_exception?(job, error)

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
