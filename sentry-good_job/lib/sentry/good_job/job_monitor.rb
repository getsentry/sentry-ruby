# frozen_string_literal: true

# Unified job monitoring for Sentry GoodJob integration
# Combines context setting, tracing, and cron monitoring in a single class
module Sentry
  module GoodJob
    class JobMonitor
      def self.setup_for_job_class(job_class)
        return unless defined?(::Rails) && ::Sentry.initialized?

        # Include Sentry::Cron::MonitorCheckIns module for cron monitoring
        # only patch if not explicitly included in job by user
        unless job_class.ancestors.include?(Sentry::Cron::MonitorCheckIns)
          job_class.include(Sentry::Cron::MonitorCheckIns)
        end

        # Add Sentry context attributes
        job_class.attr_accessor :_sentry

        # Set up around_enqueue hook (only if not already set up)
        unless job_class.respond_to?(:sentry_enqueue_hook_setup)
          job_class.define_singleton_method(:sentry_enqueue_hook_setup) { true }

          job_class.around_enqueue do |job, block|
            next block.call unless ::Sentry.initialized?

            ::Sentry.with_child_span(op: "queue.publish", description: job.class.to_s) do |span|
              _sentry_set_span_data(span, id: job.job_id, queue: job.queue_name)
              block.call
            end
          end
        end

        # Set up around_perform hook with unified functionality (only if not already set up)
        unless job_class.respond_to?(:sentry_perform_hook_setup)
          job_class.define_singleton_method(:sentry_perform_hook_setup) { true }

          job_class.around_perform do |job, block|
            next block.call unless ::Sentry.initialized?

            # Set up Sentry context
            ::Sentry.clone_hub_to_current_thread
            scope = ::Sentry.get_current_scope
            if (user = job._sentry&.dig("user"))
              scope.set_user(user)
            end
            scope.set_tags(queue: job.queue_name, job_id: job.job_id)
            scope.set_contexts(active_job: _sentry_job_context(job))
            scope.set_transaction_name(job.class.name, source: :task)
            transaction = _sentry_start_transaction(scope, job._sentry&.dig("trace_propagation_headers"))

            if transaction
              scope.set_span(transaction)

              latency = ((Time.now.utc - job.enqueued_at) * 1000).to_i if job.enqueued_at
              retry_count = job.executions.is_a?(Integer) ? job.executions - 1 : 0

              _sentry_set_span_data(
                transaction,
                id: job.job_id,
                queue: job.queue_name,
                latency: latency,
                retry_count: retry_count
              )
            end

            begin
              block.call
              _sentry_finish_transaction(transaction, 200)
            rescue => error
              _sentry_finish_transaction(transaction, 500)
              raise
            end
          end
        end

        # Add convenience method for cron monitoring configuration
        job_class.define_singleton_method(:sentry_cron_monitor) do |cron_expression, timezone: nil, slug: nil|
          return unless ::Sentry.initialized?

          # Create monitor config
          monitor_config = Sentry::GoodJob::CronMonitoring::Helpers.monitor_config_from_cron(cron_expression, timezone: timezone)
          return unless monitor_config

          # Use provided slug or generate from class name
          monitor_slug = slug || Sentry::GoodJob::CronMonitoring::Helpers.monitor_slug(name)

          sentry_monitor_check_ins(slug: monitor_slug, monitor_config: monitor_config)
        end

        # Add instance methods for Sentry context
        job_class.define_method(:enqueue) do |options = {}|
          self._sentry ||= {}

          user = ::Sentry.get_current_scope&.user
          self._sentry["user"] = user if user.present?

          self._sentry["trace_propagation_headers"] = ::Sentry.get_trace_propagation_headers

          super(options)
        end

        job_class.define_method(:serialize) do
          begin
            super().tap do |job_data|
              if _sentry
                job_data["_sentry"] = _sentry.to_json
              end
            end
          rescue JSON::GeneratorError, TypeError
            # Swallow JSON serialization errors. Better to lose Sentry context than fail to serialize the job.
            super()
          end
        end

        job_class.define_method(:deserialize) do |job_data|
          super(job_data)

          begin
            self._sentry = JSON.parse(job_data["_sentry"]) if job_data["_sentry"]
          rescue JSON::ParserError
            # Swallow JSON parsing errors. Better to lose Sentry context than fail to deserialize the job.
          end
        end

        # Add private helper methods
        job_class.define_method(:_sentry_set_span_data) do |span, id:, queue:, latency: nil, retry_count: nil|
          if span
            span.set_data("messaging.message.id", id)
            span.set_data("messaging.destination.name", queue)
            span.set_data("messaging.message.receive.latency", latency) if latency
            span.set_data("messaging.message.retry.count", retry_count) if retry_count
          end
        end

        job_class.define_method(:_sentry_job_context) do |job|
          job.serialize.symbolize_keys.except(:arguments, :_sentry)
        end

        job_class.define_method(:_sentry_start_transaction) do |scope, env|
          options = {
            name: scope.transaction_name,
            source: scope.transaction_source,
            op: "queue.process",
            origin: "auto.queue.active_job"
          }

          transaction = ::Sentry.continue_trace(env, **options)
          ::Sentry.start_transaction(transaction: transaction, **options)
        end

        job_class.define_method(:_sentry_finish_transaction) do |transaction, status|
          return unless transaction

          transaction.set_http_status(status)
          transaction.finish
        end

        # Make helper methods private
        job_class.class_eval do
          private :_sentry_set_span_data, :_sentry_job_context, :_sentry_start_transaction, :_sentry_finish_transaction
        end
      end
    end
  end
end
