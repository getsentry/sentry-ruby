# frozen_string_literal: true

# GoodJob-specific extensions to sentry-rails ActiveJob integration
# This module enhances sentry-rails ActiveJob with GoodJob-specific functionality:
# - GoodJob-specific context and tags
# - GoodJob-specific span data enhancements
module Sentry
  module GoodJob
    module ActiveJobExtensions
      # Enhance sentry-rails ActiveJob context with GoodJob-specific data
      def self.enhance_sentry_context(job, base_context)
        return base_context unless job.respond_to?(:queue_name) && job.respond_to?(:executions)

        # Add GoodJob-specific context to the existing sentry-rails context
        good_job_context = {
          queue_name: job.queue_name,
          executions: job.executions,
          enqueued_at: job.enqueued_at,
          priority: job.respond_to?(:priority) ? job.priority : nil
        }

        # Merge with base context, preserving existing structure
        base_context.merge(good_job: good_job_context)
      end

      # Enhance sentry-rails ActiveJob tags with GoodJob-specific data
      def self.enhance_sentry_tags(job, base_tags)
        return base_tags unless job.respond_to?(:queue_name) && job.respond_to?(:executions)

        good_job_tags = {
          queue_name: job.queue_name,
          executions: job.executions
        }

        # Add priority if available
        if job.respond_to?(:priority)
          good_job_tags[:priority] = job.priority
        end

        base_tags.merge(good_job_tags)
      end

      # Set up GoodJob-specific ActiveJob extensions
      def self.setup
        return unless defined?(::Rails) && ::Sentry.initialized?

        # Hook into sentry-rails ActiveJob integration
        if defined?(::Sentry::Rails::ActiveJobExtensions::SentryReporter)
          enhance_sentry_reporter
        end

        # Set up GoodJob-specific ActiveJob extensions
        setup_good_job_extensions
      end

      private

      def self.enhance_sentry_reporter
        return if defined?(@reporter_enhanced) && @reporter_enhanced

        # Enhance the sentry_context method in SentryReporter
        ::Sentry::Rails::ActiveJobExtensions::SentryReporter.class_eval do
          class << self
            alias_method :original_sentry_context, :sentry_context

            def sentry_context(job)
              base_context = original_sentry_context(job)
              Sentry::GoodJob::ActiveJobExtensions.enhance_sentry_context(job, base_context)
            end
          end
        end

        @reporter_enhanced = true
      end

      def self.setup_good_job_extensions
        # Extend ActiveJob::Base with GoodJob-specific functionality
        ActiveSupport.on_load(:active_job) do
          # Add GoodJob-specific attributes and methods
          include GoodJobExtensions

          # Ensure the sentry-rails integration is properly set up
          # by checking if the ActiveJobExtensions module is already included
          if defined?(::Sentry::Rails::ActiveJobExtensions) && !ancestors.include?(::Sentry::Rails::ActiveJobExtensions)
            require "sentry/rails/active_job"
            prepend ::Sentry::Rails::ActiveJobExtensions
          end
        end
      end

      # GoodJob-specific extensions for ActiveJob
      module GoodJobExtensions
        extend ActiveSupport::Concern

        included do
          # Set up around_enqueue hook for GoodJob-specific enqueue span
          around_enqueue do |job, block|
            next block.call unless ::Sentry.initialized?

            # Create enqueue span with GoodJob-specific data
            ::Sentry.with_child_span(op: "queue.publish", description: job.class.name) do |span|
              _sentry_set_span_data(span, job)
              block.call
            end
          end

          # GoodJob-specific context is now handled through the enhanced sentry_context method
          # The sentry-rails integration handles error capturing through SentryReporter.record
        end

        private

        # Override _sentry_set_span_data to add GoodJob-specific functionality
        def _sentry_set_span_data(span, job, retry_count: nil)
          return unless span

          # Call the base implementation if it exists (from sentry-rails)
          if respond_to?(:_sentry_set_span_data, true) && method(:_sentry_set_span_data).super_method
            super(span, job, retry_count: retry_count)
          else
            # Fallback: implement base functionality directly
            span.set_data("messaging.message.id", job.job_id)
            span.set_data("messaging.destination.name", job.queue_name) if job.respond_to?(:queue_name)
            span.set_data("messaging.message.retry.count", retry_count) if retry_count
          end

          # Add GoodJob-specific span data (latency)
          latency = calculate_job_latency(job)
          span.set_data("messaging.message.receive.latency", latency) if latency
        end

        # Calculate job latency in milliseconds (GoodJob-specific)
        def calculate_job_latency(job)
          return nil unless job.enqueued_at

          ((Time.now.utc - job.enqueued_at) * 1000).to_i
        end
      end
    end
  end
end
