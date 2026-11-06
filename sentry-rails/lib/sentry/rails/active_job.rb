# frozen_string_literal: true

require "set"
require "sentry/rails/serializer"
require "sentry/rails/error_reporter_context"
require "sentry/rails/active_job_extension"

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
          SentryReporter.record(self) { super }
        end
      end

      def serialize
        payload = super
        return payload if !Sentry.initialized? || already_supported_by_sentry_integration?
        SentryReporter.prepare_payload(self, payload)
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
        OP_NAME = Sentry::JobExtensions::Extension::PROCESS_OP
        SPAN_ORIGIN = ActiveJobExtension::SPAN_ORIGIN
        MESSAGING_SYSTEM_FALLBACK = "activejob"

        EVENT_HANDLERS = {
          "enqueue_retry.active_job" => :retry_handler
        }

        class << self
          def prepare_payload(job, payload)
            Sentry::Rails.active_job_extension_for(job.class).prepare_payload(job: job, payload: payload)
          end

          def producer_callback_registered?
            @producer_callback_registered ||= false
          end

          def producer_callback_registered!
            @producer_callback_registered = true
          end

          def record_producer_span(job, &enqueue)
            return yield if !Sentry.initialized? || job.already_supported_by_sentry_integration?

            Sentry::Rails.active_job_extension_for(job.class).instrument_enqueue(job: job, &enqueue)
          end

          def record(job, &block)
            with_isolated_scope do |scope|
              record_in_scope(scope, job, &block)
            end
          end

          def record_in_scope(scope, job)
            extension = Sentry::Rails.active_job_extension_for(job.class)
            transaction = nil

            begin
              transaction = extension.start_job(scope: scope, job: job)

              yield.tap do
                extension.finish_job(transaction: transaction, status: 200)
              end
            rescue Exception => e # rubocop:disable Lint/RescueException
              extension.finish_job(transaction: transaction, status: 500)

              if extension.safely("decide whether to report the job exception", fallback: true) { extension.report_exception?(job: job, exception: e) }
                extension.capture_exception(job: job, exception: e)
              end

              raise
            end
          end

          def capture_exception(job, e)
            Sentry::Rails.active_job_extension_for(job.class).capture_exception(job: job, exception: e)
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

              extension = Sentry::Rails.active_job_extension_for(job.class)
              report = extension.safely("decide whether to report the retried exception", fallback: Sentry.configuration.rails.active_job_report_on_retry_error) do
                extension.report_retried_exception?(job: job, exception: error)
              end
              return unless report

              extension.capture_exception(job: job, exception: error)
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
