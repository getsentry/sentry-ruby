# frozen_string_literal: true

module Sentry
  module Rails
    module ActiveJobExtensions
      class JobExtension
        class Producer < Sentry::JobExtensions::Producer
          def prepare_payload(job, payload)
            sentry_data = {}
            if Sentry.configuration.rails.active_job_propagate_traces
              headers = Sentry.get_trace_propagation_headers
              if headers && !headers.empty?
                sentry_data["trace_propagation_headers"] = headers
                payload = inject_trace_headers(job, payload, headers)
              end
            end

            if Sentry.configuration.data_collection.user_info
              user = Sentry.get_current_scope.user.transform_keys(&:to_s).slice(*USER_FIELDS_ALLOWLIST)
              sentry_data["user"] = user unless user.empty?
            end

            sentry_data.empty? ? payload : payload.merge(SENTRY_PAYLOAD_KEY => sentry_data)
          rescue StandardError => e
            Sentry.sdk_logger&.error("sentry-rails: failed to inject _sentry payload: #{e.class}: #{e.message}\n  #{Array(e.backtrace).first(5).join("\n  ")}")
            payload
          end

          def record_span(job, &enqueue)
            super(job, on_instrumentation_error: method(:log_producer_span_error), &enqueue)
          end

          private

          def log_producer_span_error(e)
            Sentry.sdk_logger&.error("sentry-rails: failed to record producer span: #{e.class}: #{e.message}\n  #{Array(e.backtrace).first(5).join("\n  ")}")
          end
        end
      end
    end
  end
end
