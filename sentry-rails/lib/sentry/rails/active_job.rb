# frozen_string_literal: true

require "set"
require "sentry/rails/serializer"
require "sentry/rails/error_reporter_context"
require "sentry/rails/active_job/job_extension"
require "sentry/rails/active_job/producer"

module Sentry
  module Rails
    module ActiveJobExtensions
      SENTRY_PAYLOAD_KEY = "_sentry"

      def self.prepended(base)
        base.attr_accessor :_sentry
        base.attr_reader :_sentry_job_data
      end

      def perform_now
        if !Sentry.initialized? || already_supported_by_sentry_integration?
          super
        else
          data = _sentry || {}
          current_scope = Sentry.get_current_scope
          scope = current_scope if data["execution_scope_id"] == current_scope.object_id
          transaction = scope&.get_span
          SentryReporter.record(
            self,
            trace_headers: data["trace_propagation_headers"],
            user: data["user"],
            payload: _sentry_job_data,
            transaction: transaction,
            scope: scope
          ) { super }
        end
      end

      def serialize
        payload = super
        return payload if !Sentry.initialized? || already_supported_by_sentry_integration?
        SentryReporter.producer(self).prepare_payload(self, payload)
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
        EVENT_HANDLERS = {
          "enqueue_retry.active_job" => :retry_handler
        }

        class << self
          def default_extension
            @default_extension ||= JobExtension.new
          end

          def consumer
            @consumer ||= Sentry::JobExtensions::Consumer.new(integration: Sentry::Rails, origin: JobExtension::SPAN_ORIGIN, registry: job_extensions)
          end

          def producer(job)
            job_extensions.call(job_extensions.for(job), :producer, job: job)
          end

          def job_extensions
            default_extension.registry
          end

          def producer_callback_registered?
            @producer_callback_registered ||= false
          end

          def producer_callback_registered!
            @producer_callback_registered = true
          end

          def record_producer_span(job, &enqueue)
            return yield if !Sentry.initialized? || job.already_supported_by_sentry_integration?
            producer(job).record_span(job, &enqueue)
          end

          def record(job, trace_headers: nil, user: nil, payload: nil, transaction: nil, scope: nil, &block)
            options = { trace_headers: trace_headers, user: user, payload: payload, transaction: transaction }
            return record_in_scope(scope, job, **options, backend_scope: true, &block) if scope

            with_isolated_scope do |isolated_scope|
              record_in_scope(isolated_scope, job, **options, &block)
            end
          end

          def record_in_scope(scope, job, trace_headers: nil, user: nil, payload: nil, transaction: nil, backend_scope: false)
            begin
              scope.set_user(user.transform_keys(&:to_sym)) if user && !user.empty?

              consumer.apply_scope_data(scope, job)

              scope.set_transaction_name(consumer.transaction_name(job), source: :task)

              transaction = consumer.start_transaction(
                scope, job,
                transaction: transaction.is_a?(Sentry::Transaction) ? transaction : nil,
                trace_headers: trace_headers,
                payload: payload
              )

              yield.tap do
                consumer.finish_transaction(transaction, 200)
              end
            rescue Exception => e # rubocop:disable Lint/RescueException
              consumer.finish_transaction(transaction, 500)

              if backend_scope
                scope.update_from_options(**default_extension.error_data(job: job, exception: e))
              elsif consumer.report_exception?(job, e)
                capture_exception(job, e)
              end

              raise
            end
          end

          def capture_exception(job, e)
            consumer.capture_exception(job, e, **default_extension.error_data(job: job, exception: e))
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
              return unless consumer.report_retried_exception?(job, error, default: nil)

              capture_exception(job, error)
            end
          end

          def handle_error_event(*args)
            event = ActiveSupport::Notifications::Event.new(*args)
            yield(event.payload[:job], event.payload[:error])
          end

          private :record_in_scope

          private

          def with_isolated_scope(&block)
            original_hub = Sentry.get_current_hub_internal
            Sentry.clone_hub_to_current_thread
            Sentry.with_scope(&block)
          ensure
            Sentry.set_current_hub_internal(original_hub)
          end

          def subscribers
            @__subscribers__ ||= Set.new
          end
        end
      end
    end
  end
end
