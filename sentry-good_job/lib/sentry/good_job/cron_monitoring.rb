# frozen_string_literal: true

# Sentry Cron Monitoring for Good Job
# This module provides comprehensive cron monitoring for Good Job scheduled tasks
# Following Good Job's extension patterns and Sentry's integration guidelines
module Sentry
  module GoodJob
    module CronMonitoring
      # Utility methods for cron parsing and configuration
      # These methods handle the conversion between Good Job cron expressions and Sentry monitor configs
      module Helpers
        # Parse cron expression and create Sentry monitor config
        def self.monitor_config_from_cron(cron_expression, timezone: nil)
          return nil unless cron_expression.present?

          # Parse cron expression using fugit (same as Good Job)
          parsed_cron = Fugit.parse_cron(cron_expression)
          return nil unless parsed_cron

          # Convert to Sentry monitor config
          if timezone.present?
            ::Sentry::Cron::MonitorConfig.from_crontab(cron_expression, timezone: timezone)
          else
            ::Sentry::Cron::MonitorConfig.from_crontab(cron_expression)
          end
        rescue => e
          Sentry::GoodJob::Logger.warn "Failed to parse cron expression '#{cron_expression}': #{e.message}"
          nil
        end

        # Generate monitor slug from job name
        def self.monitor_slug(job_name)
          job_name.to_s.underscore.gsub(/_job$/, "")
        end

        # Parse cron expression and extract timezone
        def self.parse_cron_with_timezone(cron_expression)
          return [cron_expression, nil] unless cron_expression.present?

          parts = cron_expression.strip.split(" ")
          return [cron_expression, nil] unless parts.length > 5

          # Last part might be timezone
          timezone = parts.last
          # Basic timezone validation (matches common timezone formats including Europe/Stockholm, America/New_York, etc.)
          if timezone.match?(/^[A-Za-z_]+\/[A-Za-z_]+$/) || timezone.match?(/^[A-Za-z_]+$/)
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
        # Set up monitoring for all scheduled jobs from Good Job configuration
        def self.setup_monitoring_for_scheduled_jobs
          return unless ::Sentry.initialized?
          return unless ::Sentry.configuration.good_job.auto_setup_cron_monitoring

          cron_config = ::Rails.application.config.good_job.cron
          return unless cron_config.present?

          cron_config.each do |job_name, job_config|
            setup_monitoring_for_job(job_name, job_config)
          end

          Sentry::GoodJob::Logger.info "Sentry cron monitoring setup for #{cron_config.keys.size} scheduled jobs"
        end

        # Set up monitoring for a specific job
        def self.setup_monitoring_for_job(job_name, job_config)
          job_class_name = job_config[:class]
          cron_expression = job_config[:cron]

          return unless job_class_name && cron_expression

          # Get the job class
          job_class = begin
            job_class_name.constantize
          rescue NameError => e
            Sentry::GoodJob::Logger.warn "Could not find job class '#{job_class_name}' for Sentry cron monitoring: #{e.message}"
            return
          end

          # Set up job monitoring if not already set up
          Sentry::GoodJob::JobMonitor.setup_for_job_class(job_class)

          # Parse cron expression and create monitor config
          cron_without_tz, timezone = Sentry::GoodJob::CronMonitoring::Helpers.parse_cron_with_timezone(cron_expression)
          monitor_config = Sentry::GoodJob::CronMonitoring::Helpers.monitor_config_from_cron(cron_without_tz, timezone: timezone)

          if monitor_config
            # Configure Sentry cron monitoring - use job_name as slug for consistency
            monitor_slug = Sentry::GoodJob::CronMonitoring::Helpers.monitor_slug(job_name)

            # only patch if not explicitly included in job by user
            unless job_class.ancestors.include?(Sentry::Cron::MonitorCheckIns)
              job_class.include(Sentry::Cron::MonitorCheckIns)
            end

            job_class.sentry_monitor_check_ins(
              slug: monitor_slug,
              monitor_config: monitor_config
            )

            Sentry::GoodJob::Logger.info "Added Sentry cron monitoring for #{job_class_name} (#{monitor_slug})"
          else
            Sentry::GoodJob::Logger.warn "Could not create monitor config for #{job_class_name} with cron '#{cron_expression}'"
          end
        end

        # Manually add cron monitoring to a specific job
        def self.add_monitoring_to_job(job_class, slug: nil, cron_expression: nil, timezone: nil)
          return unless ::Sentry.initialized?

          # Set up job monitoring if not already set up
          Sentry::GoodJob::JobMonitor.setup_for_job_class(job_class)

          # Create monitor config
          monitor_config = if cron_expression
            Sentry::GoodJob::CronMonitoring::Helpers.monitor_config_from_cron(cron_expression, timezone: timezone)
          else
            # Default to hourly monitoring if no cron expression provided
            ::Sentry::Cron::MonitorConfig.from_crontab("0 * * * *")
          end

          if monitor_config
            monitor_slug = slug || Sentry::GoodJob::CronMonitoring::Helpers.monitor_slug(job_class.name)

            # only patch if not explicitly included in job by user
            unless job_class.ancestors.include?(Sentry::Cron::MonitorCheckIns)
              job_class.include(Sentry::Cron::MonitorCheckIns)
            end

            job_class.sentry_monitor_check_ins(
              slug: monitor_slug,
              monitor_config: monitor_config
            )

            Sentry::GoodJob::Logger.info "Added Sentry cron monitoring for #{job_class.name} (#{monitor_slug})"
          end
        end
      end
    end
  end
end
