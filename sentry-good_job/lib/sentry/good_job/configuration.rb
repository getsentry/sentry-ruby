# frozen_string_literal: true

module Sentry
  class Configuration
    attr_reader :good_job

    add_post_initialization_callback do
      @good_job = Sentry::GoodJob::Configuration.new
      @excluded_exceptions = @excluded_exceptions.concat(Sentry::GoodJob::IGNORE_DEFAULT)
    end
  end

  module GoodJob
    IGNORE_DEFAULT = [
      "ActiveJob::DeserializationError",
      "ActiveJob::SerializationError"
    ]

    class Configuration
      # Set this option to true if you want Sentry to only capture the last job
      # retry if it fails.
      attr_accessor :report_after_job_retries

      # Only report jobs that have retry_on_attempts set (i.e., jobs that can be retried)
      attr_accessor :report_only_dead_jobs

      # Whether we should inject headers while enqueuing the job in order to have a connected trace
      attr_accessor :propagate_traces

      # Whether to include job arguments in error context (be careful with sensitive data)
      attr_accessor :include_job_arguments

      # Whether to automatically set up cron monitoring for all scheduled jobs
      attr_accessor :auto_setup_cron_monitoring

      # When false, suppresses all Sentry GoodJob integration logs
      attr_accessor :logging_enabled

      # Custom logger to use for Sentry GoodJob integration (defaults to Rails.logger)
      attr_accessor :logger

      def initialize
        @report_after_job_retries = false
        @report_only_dead_jobs = false
        @propagate_traces = true
        @include_job_arguments = false
        @auto_setup_cron_monitoring = true
        @logging_enabled = false
        @logger = nil
      end
    end
  end
end
