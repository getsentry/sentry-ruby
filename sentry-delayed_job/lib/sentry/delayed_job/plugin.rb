# frozen_string_literal: true

require "delayed_job"

module Sentry
  module DelayedJob
    class Plugin < ::Delayed::Plugin
      # need to symbolize strings as keyword arguments in Ruby 2.4~2.6
      DELAYED_JOB_CONTEXT_KEY = :"Delayed-Job"
      ACTIVE_JOB_CONTEXT_KEY = :"Active-Job"
      OP_NAME = "queue.delayed_job"
      SPAN_ORIGIN = "auto.queue.delayed_job"
      PROCESS_OP_NAME = "queue.process"

      callbacks do |lifecycle|
        lifecycle.before(:enqueue) do |job, *args, &block|
          monitor_job_enqueue(job) if Sentry.initialized?
        end

        lifecycle.around(:invoke_job) do |job, *args, &block|
          monitor_job_execution(job, *args, &block)
        end
      end

      def self.set_span_data(span, job:)
        return unless span

        # Set messaging conventions data similar to Sidekiq implementation
        span.set_data(Sentry::Span::DataConventions::MESSAGING_MESSAGE_ID, job.id.to_s)
        span.set_data(Sentry::Span::DataConventions::MESSAGING_DESTINATION_NAME, job.queue || "default")

        # Calculate and set latency if the job has been enqueued
        if job.run_at && job.created_at
          latency_ms = calculate_latency(job)
          span.set_data(Sentry::Span::DataConventions::MESSAGING_MESSAGE_RECEIVE_LATENCY, latency_ms) if latency_ms
        end

        # Set retry count
        span.set_data(Sentry::Span::DataConventions::MESSAGING_MESSAGE_RETRY_COUNT, job.attempts) if job.attempts > 0
      end

      def self.calculate_latency(job)
        return nil unless job.run_at && job.created_at

        # Calculate latency in milliseconds
        now = Time.current
        enqueued_at = job.created_at
        scheduled_at = job.run_at

        # If the job was scheduled for the future, use the scheduled time
        # Otherwise use the enqueued time
        start_time = [scheduled_at, enqueued_at].max

        # Calculate latency from when the job should have run to now
        latency_seconds = now - start_time
        (latency_seconds * 1000).round
      end

      def self.capture_enqueue_context(job)
        # Extract user context if available (from Active Job)
        return nil unless job.payload_object.respond_to?(:job_data)

        job.payload_object.job_data["sentry_user"]
      end

      def self.monitor_job_enqueue(job)
        # Add queue metrics for enqueue
        current_span = Sentry.get_current_scope&.span

        # Check if current span is active and not already finished
        if current_span && current_span.timestamp.nil?
          # Inject trace data first with the parent span context
          inject_trace_data(job)

          # Then create a child span for monitoring
          Sentry.with_child_span(op: "queue.publish", description: compute_job_class(job.payload_object)) do |span|
            if span
              set_span_data(span, job: job)
              # Mark the span as successful
              span.set_status("ok")
            end
          end
        else
          # Fallback: just inject trace data without creating transactions
          inject_trace_data(job)
        end
      end

      def self.monitor_job_execution(job, *args, &block)
        env = extract_trace_data(job)
        return block.call(job, *args) unless Sentry.initialized?

        Sentry.clone_hub_to_current_thread

        Sentry.with_scope do |scope|
          contexts = generate_contexts(job)

          if (user = capture_enqueue_context(job))
            scope.set_user(user)
          end

          name = contexts.dig(ACTIVE_JOB_CONTEXT_KEY, :job_class) || contexts.dig(DELAYED_JOB_CONTEXT_KEY, :job_class)
          scope.set_transaction_name(name, source: :task)
          scope.set_contexts(**contexts)
          scope.set_tags("delayed_job.queue" => job.queue, "delayed_job.id" => job.id.to_s)

          transaction = start_transaction(scope, env, contexts)
          scope.set_span(transaction) if transaction

          begin
            if transaction
              # Create a queue.process child span for the actual job processing
              # This follows Sentry's queues module documentation
              Sentry.with_child_span(op: PROCESS_OP_NAME, description: compute_job_class(job.payload_object)) do |span|
                # Add queue usage reporting data to the processing span
                set_span_data(span, job: job) if span

                block.call(job, *args)

                # Mark the span as successful
                span&.set_status("ok")
              end

              finish_transaction(transaction, 200)
            else
              # Fallback if no transaction could be created
              block.call(job, *args)
            end
          rescue Exception => e
            # Mark the transaction and span as failed
            transaction&.set_status("internal_error")
            capture_exception(e, job)
            finish_transaction(transaction, 500)
            raise
          end
        end
      end

      def self.generate_contexts(job)
        context = {}

        context[DELAYED_JOB_CONTEXT_KEY] = {
          id: job.id.to_s,
          priority: job.priority,
          attempts: job.attempts,
          run_at: job.run_at,
          locked_at: job.locked_at,
          locked_by: job.locked_by,
          queue: job.queue,
          created_at: job.created_at,
          last_error: job.last_error&.byteslice(0..1000),
          handler: job.handler&.byteslice(0..1000),
          job_class: compute_job_class(job.payload_object)
        }

        if job.payload_object.respond_to?(:job_data)
          context[ACTIVE_JOB_CONTEXT_KEY] = {}

          job.payload_object.job_data.each do |key, value|
            context[ACTIVE_JOB_CONTEXT_KEY][key.to_sym] = value
          end
        end

        context
      end

      def self.compute_job_class(payload_object)
        if payload_object.is_a?(Delayed::PerformableMethod)
          klass = payload_object.object.is_a?(Class) ? payload_object.object.name : payload_object.object.class.name
          "#{klass}##{payload_object.method_name}"
        else
          payload_object.class.name
        end
      end

      def self.capture_exception(exception, job)
        Sentry::DelayedJob.capture_exception(exception, hint: { background: false }) if report?(job)
      end

      def self.report?(job)
        return true unless Sentry.configuration.delayed_job.report_after_job_retries

        # We use the predecessor because the job's attempts haven't been increased to the new
        # count at this point.
        max_attempts = job&.max_attempts&.pred || Delayed::Worker.max_attempts.pred
        job.attempts >= max_attempts
      end

      def self.start_transaction(scope, env, contexts)
        options = {
          name: scope.transaction_name,
          source: scope.transaction_source,
          op: OP_NAME,
          origin: SPAN_ORIGIN
        }

        transaction = Sentry.continue_trace(env, **options)
        Sentry.start_transaction(transaction: transaction, custom_sampling_context: contexts, **options)
      end

      def self.finish_transaction(transaction, status)
        return unless transaction

        transaction.set_http_status(status)
        transaction.finish
      end

      def self.inject_trace_data(job)
        # active job style is handled in the sentry-rails/active_job extension more generally
        # if someone enqueues manually with some other job class, we cannot make assumptions unfortunately
        payload_object = job.payload_object
        return unless payload_object.is_a?(Delayed::PerformableMethod)

        # we will add the trace data to args and remove it again
        # this is hacky but it's the only reliable way to survive the YAML serialization/deserialization
        payload_object.args << { sentry: Sentry.get_trace_propagation_headers }
        job.payload_object = payload_object
      end

      def self.extract_trace_data(job)
        payload_object = job.payload_object
        return nil unless payload_object.is_a?(Delayed::PerformableMethod)

        target_payload = payload_object.args.find { |a| a.is_a?(Hash) && a.key?(:sentry) }
        return nil unless target_payload
        payload_object.args.delete(target_payload)
        target_payload[:sentry]
      end
    end
  end
end

Delayed::Worker.plugins << Sentry::DelayedJob::Plugin
