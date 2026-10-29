# frozen_string_literal: true

module Sentry
  module JobExtensions
    # @api private
    class Consumer < Instrumentation
      OP_NAME = "queue.process"

      attr_reader :integration, :origin

      def initialize(integration:, origin:, registry: Sentry.job_extensions)
        super(registry: registry)
        @integration = integration
        @origin = origin
      end

      def apply_scope_data(scope, job, default_scope_data: {})
        apply_scope_values(scope, default_scope_data)
        data = registry.call(registry.for(job), :scope_data, job: job)
        apply_scope_values(scope, data)
      end

      def transaction_name(job)
        registry.call(registry.for(job), :transaction_name, job: job)
      end

      def start_transaction(scope, job, transaction: nil, trace_headers: nil, payload: nil, always_continue_trace: false, messaging_data: {}, default_retry_count: nil)
        extension = registry.for(job)
        options = {
          name: scope.transaction_name,
          source: scope.transaction_source,
          op: OP_NAME,
          origin: registry.call(extension, :span_origin, job: job) || origin
        }

        if (trace_headers.nil? || trace_headers.empty?) && payload
          extracted_headers = registry.call(extension, :extract_trace_headers, job: job, payload: payload)

          unless extracted_headers.nil?
            trace_headers = extracted_headers
            always_continue_trace = true
          end
        end

        if transaction
          transaction.set_name(options[:name], source: options[:source])
          transaction.set_origin(options[:origin])
        else
          transaction = if always_continue_trace || (trace_headers && !trace_headers.empty?)
            continued = Sentry.continue_trace(trace_headers, **options)
            Sentry.start_transaction(transaction: continued, **options)
          else
            Sentry.start_transaction(**options)
          end
        end
        return unless transaction

        scope.set_span(transaction)
        set_messaging_data(transaction, resolve(messaging_data).reject { |_key, value| value.nil? })
        set_messaging_data(transaction, registry.call(extension, :messaging_data, job: job))
        set_retry_count(transaction, extension, job, default: resolve(default_retry_count))

        transaction
      end

      def finish_transaction(transaction, status)
        return if !transaction || transaction.timestamp

        transaction.set_http_status(status)
        transaction.finish
      end

      def will_retry?(job)
        info = registry.call(registry.for(job), :retry_info, job: job)
        info ? info[:will_retry] : false
      end

      def report_exception?(job, exception)
        decision = registry.call(registry.for(job), :report_exception?, job: job, exception: exception)
        decision.nil? ? !will_retry?(job) : decision
      end

      def report_retried_exception?(job, exception, default:)
        decision = registry.call(registry.for(job), :report_retried_exception?, job: job, exception: exception)
        decision.nil? ? default : decision
      end

      def capture_exception(job, exception, contexts: {}, tags: {}, extra: {})
        extension = registry.for(job)
        error_data = additive_error_data(
          registry.call(extension, :error_data, job: job, exception: exception)
        )

        options = {
          extra: error_data[:extra].merge(matching_keys(extra, error_data[:extra])),
          tags: error_data[:tags].merge(matching_keys(tags, error_data[:tags])),
          hint: { background: false }
        }
        contexts = error_data[:contexts].merge(matching_keys(contexts, error_data[:contexts]))
        options[:contexts] = contexts unless contexts.empty?

        capturing_integration = registry.call(extension, :integration, job: job) || integration
        capturing_integration.capture_exception(exception, **options)
      end

      private

      def apply_scope_values(scope, data)
        scope.set_contexts(data[:contexts]) if data[:contexts]
        scope.set_tags(data[:tags]) if data[:tags]
        scope.set_extras(data[:extra]) if data[:extra]
        scope.set_user(data[:user]) if data[:user]
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
    end
  end
end
