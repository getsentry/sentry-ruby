# frozen_string_literal: true

# Sentry Cron Monitoring for Active Job
# This module provides comprehensive cron monitoring for Active Job scheduled tasks
# It works with any Active Job adapter, including GoodJob
# Following Active Job's extension patterns and Sentry's integration guidelines
module Sentry
  module GoodJob
    module CronHelpers
      # Utility methods for cron parsing and configuration
      # These methods handle the conversion between Good Job cron expressions and Sentry monitor configs
      module Helpers
        # Parse cron expression and create Sentry monitor config
        def self.monitor_config_from_cron(cron_expression, timezone: nil)
          return nil unless cron_expression && !cron_expression.strip.empty?

          # Parse cron expression using fugit (same as Good Job)
          parsed_cron = Fugit.parse_cron(cron_expression)
          return nil unless parsed_cron

          # Convert to Sentry monitor config
          if timezone && !timezone.strip.empty?
            ::Sentry::Cron::MonitorConfig.from_crontab(cron_expression, timezone: timezone)
          else
            ::Sentry::Cron::MonitorConfig.from_crontab(cron_expression)
          end
        rescue => e
          Sentry.configuration.sdk_logger.warn "Failed to parse cron expression '#{cron_expression}': #{e.message}"
          nil
        end

        # Generate monitor slug from job name
        def self.monitor_slug(job_name)
          job_name.to_s.underscore.gsub(/_job$/, "")
        end

        # Parse cron expression and extract timezone
        def self.parse_cron_with_timezone(cron_expression)
          return [cron_expression, nil] unless cron_expression && !cron_expression.strip.empty?

          parts = cron_expression.strip.split(" ")
          return [cron_expression, nil] unless parts.length > 5

          # Last part might be timezone
          timezone = parts.last
          # Comprehensive timezone validation that handles:
          # - Standard timezone names (UTC, GMT)
          # - IANA timezone identifiers (America/New_York, Europe/Stockholm)
          # - Multi-level IANA timezones (America/Argentina/Buenos_Aires)
          # - UTC offsets (UTC+2, UTC-5, GMT+1, GMT-8)
          # - Numeric timezones (GMT-5, UTC+2)
          if timezone.match?(/^[A-Za-z_]+$/) || # Simple timezone names (UTC, GMT, EST, etc.)
             timezone.match?(/^[A-Za-z_]+\/[A-Za-z_]+$/) || # Single slash timezones (Europe/Stockholm)
             timezone.match?(/^[A-Za-z_]+\/[A-Za-z_]+\/[A-Za-z_]+$/) || # Multi-slash timezones (America/Argentina/Buenos_Aires)
             timezone.match?(/^[A-Za-z_]+[+-]\d+$/) || # UTC/GMT offsets (UTC+2, GMT-5)
             timezone.match?(/^[A-Za-z_]+\/[A-Za-z_]+[+-]\d+$/) # IANA with offset (Europe/Stockholm+1)
            cron_without_timezone = cron_expression.gsub(/\s+#{Regexp.escape(timezone)}$/, "")
            [cron_without_timezone, timezone]
          else
            [cron_expression, nil]
          end
        end
      end

      # Main integration class that handles all cron monitoring setup
      # This class follows Good Job's integration patterns and Sentry's extension guidelines
      class Integration
        # Track whether setup has already been performed to prevent duplicates
        @setup_completed = false
        @reload_hooked = false

        # Set up monitoring for all scheduled jobs from Good Job configuration
        def self.setup_monitoring_for_scheduled_jobs
          return unless ::Sentry.initialized?
          return unless ::Sentry.configuration.good_job.enable_cron_monitors
          attach_reload_hook_if_available
          return if @setup_completed

          return unless defined?(::Rails) && ::Rails.respond_to?(:application) && ::Rails.application
          cron_config = ::Rails.application.config.good_job.cron
          return unless cron_config.present?

          added_jobs = []
          cron_config.each do |cron_key, job_config|
            job_name = setup_monitoring_for_job(cron_key, job_config)
            added_jobs << job_name if job_name
          end

          @setup_completed = true
          if added_jobs.any?
            job_list = added_jobs.join(", ")
            Sentry.configuration.sdk_logger.info "Sentry cron monitoring setup for #{added_jobs.size} scheduled jobs: #{job_list}"
          else
            Sentry.configuration.sdk_logger.info "Sentry cron monitoring setup for #{cron_config.keys.size} scheduled jobs"
          end
        end

        # Reset setup state (primarily for testing)
        def self.reset_setup_state!
          @setup_completed = false
        end

        # Set up monitoring for a specific job
        def self.setup_monitoring_for_job(cron_key, job_config)
          job_class_name = job_config[:class]
          cron_expression = job_config[:cron]

          return unless job_class_name && cron_expression

          # Defer job class constantization to avoid boot-time issues
          # The job class will be constantized when the job is actually executed
          # This prevents issues during development boot and circular dependencies

          # Store the monitoring configuration for later use
          # We'll set up the monitoring when the job class is first loaded
          deferred_setup = lambda do
            job_class = begin
              job_class_name.constantize
            rescue NameError => e
              Sentry.configuration.sdk_logger.warn "Could not find job class '#{job_class_name}' for Sentry cron monitoring: #{e.message}"
              return
            end

            # Include Sentry::Cron::MonitorCheckIns module for cron monitoring
            # only patch if not explicitly included in job by user
            unless job_class.ancestors.include?(Sentry::Cron::MonitorCheckIns)
              job_class.include(Sentry::Cron::MonitorCheckIns)
            end

            # Parse cron expression and create monitor config
            cron_without_tz, timezone = Sentry::GoodJob::CronHelpers::Helpers.parse_cron_with_timezone(cron_expression)
            monitor_config = Sentry::GoodJob::CronHelpers::Helpers.monitor_config_from_cron(cron_without_tz, timezone: timezone)

            if monitor_config
              # Configure Sentry cron monitoring - use cron_key as slug for consistency
              monitor_slug = Sentry::GoodJob::CronHelpers::Helpers.monitor_slug(cron_key)

              job_class.sentry_monitor_check_ins(
                slug: monitor_slug,
                monitor_config: monitor_config
              )

              job_class_name
            else
              Sentry.configuration.sdk_logger.warn "Could not create monitor config for #{job_class_name} with cron '#{cron_expression}'"
              nil
            end
          end

          # Set up monitoring when the job class is first loaded
          # This defers constantization until the job is actually needed
          if defined?(::Rails) && ::Rails.respond_to?(:application) && ::Rails.application
            ::Rails.application.config.after_initialize do
              deferred_setup.call
            end
          else
            # Fallback for non-Rails environments
            deferred_setup.call
          end

          # Return the job name for logging purposes
          job_class_name
        end

        # Manually add cron monitoring to a specific job
        def self.add_monitoring_to_job(job_class, slug: nil, cron_expression: nil, timezone: nil)
          return unless ::Sentry.initialized?

          # Include Sentry::Cron::MonitorCheckIns module for cron monitoring
          # only patch if not explicitly included in job by user
          unless job_class.ancestors.include?(Sentry::Cron::MonitorCheckIns)
            job_class.include(Sentry::Cron::MonitorCheckIns)
          end

          # Create monitor config
          monitor_config = if cron_expression
            Sentry::GoodJob::CronHelpers::Helpers.monitor_config_from_cron(cron_expression, timezone: timezone)
          else
            # Default to hourly monitoring if no cron expression provided
            ::Sentry::Cron::MonitorConfig.from_crontab("0 * * * *")
          end

          if monitor_config
            monitor_slug = slug || Sentry::GoodJob::CronHelpers::Helpers.monitor_slug(job_class.name)

            job_class.sentry_monitor_check_ins(
              slug: monitor_slug,
              monitor_config: monitor_config
            )

            Sentry.configuration.sdk_logger.info "Added Sentry cron monitoring for #{job_class.name} (#{monitor_slug})"
          end
        end

        def self.attach_reload_hook_if_available
          return if @reload_hooked
          return unless defined?(::ActiveSupport::Reloader)

          ::ActiveSupport::Reloader.to_prepare do
            @setup_completed = false
          end

          @reload_hooked = true
        rescue NameError
          # ActiveSupport::Reloader not available in this environment
        end
      end
    end
  end
end
