# frozen_string_literal: true

module Sentry
  module Resque
    # Sends Crons check-ins for resque-scheduler `cron` and `every` schedules.
    # Enable with `config.enabled_patches << :resque_scheduler`.
    module Scheduler
      PAYLOAD_KEY = "sentry_monitor"
      CURRENT_MONITOR = :sentry_resque_scheduler_monitor

      module SchedulerPatch
        def load_schedule_job(name, config)
          ret = super
          # Monitored here, so the :rufus_scheduler patch skips them.
          job = scheduled_jobs && scheduled_jobs[name]
          job.opts[:sentry_monitor] = false if job.respond_to?(:opts) && job.opts.is_a?(Hash)
          ret
        end

        private

        def enqueue_recurring(name, config)
          Thread.current[CURRENT_MONITOR] = Sentry::Resque::Scheduler.monitor_for(name, scheduled_jobs && scheduled_jobs[name])
          super
        ensure
          Thread.current[CURRENT_MONITOR] = nil
        end
      end

      module Push
        def push(queue, item)
          monitor = Thread.current[CURRENT_MONITOR]
          if monitor && item.is_a?(Hash)
            # Only the scheduled job, not jobs pushed by its enqueue hooks.
            Thread.current[CURRENT_MONITOR] = nil
            item = item.merge(PAYLOAD_KEY => monitor)
          end
          super(queue, item)
        end
      end

      module Job
        def perform
          data = payload[PAYLOAD_KEY] if payload.is_a?(Hash)
          return super unless data.is_a?(Hash) && Sentry.initialized?

          Sentry::Resque::Scheduler.check_in(data) { super }
        end
      end

      class << self
        def excluded?(name)
          Array(Sentry.configuration.resque.exclude_scheduled_jobs).any? { |pattern| pattern === name.to_s }
        rescue StandardError => e
          Sentry.sdk_logger.error(Sentry::LOGGER_PROGNAME) { "Could not check exclude_scheduled_jobs for #{name}: #{e.class}: #{e.message}" }
          false
        end

        # Runs in the scheduler, which is where rufus-scheduler evaluates the schedule.
        def monitor_for(name, rufus_job)
          return unless rufus_job && Sentry.initialized?
          return if excluded?(name)

          slug = name.to_s.downcase.gsub(/[^a-z0-9_-]+/, "-").gsub(/\A-+|-+\z/, "")
          slug = slug[0, Sentry::Cron::MonitorCheckIns::MAX_SLUG_LENGTH].delete_suffix("-")
          return if slug.empty?

          config =
            case rufus_job
            when ::Rufus::Scheduler::CronJob then Sentry::Cron::FugitSchedule.from_cron(rufus_job.cron_line)
            when ::Rufus::Scheduler::EveryJob then Sentry::Cron::FugitSchedule.from_seconds(rufus_job.frequency)
            end
          { "slug" => slug, "schedule" => config&.schedule&.to_h, "timezone" => config&.timezone }.compact
        rescue StandardError => e
          Sentry.sdk_logger.error(Sentry::LOGGER_PROGNAME) { "Not monitoring resque-scheduler job #{name}: #{e.class}: #{e.message}" }
          nil
        end

        def check_in(data)
          slug = data["slug"]
          monitor_config = monitor_config_for(data)
          check_in_id = Sentry.capture_check_in(slug, :in_progress, monitor_config: monitor_config)
          start = Process.clock_gettime(Process::CLOCK_MONOTONIC)

          begin
            ret = yield
          rescue Exception
            duration = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start
            Sentry.capture_check_in(slug, :error, check_in_id: check_in_id, duration: duration, monitor_config: monitor_config)
            raise
          end

          duration = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start
          Sentry.capture_check_in(slug, :ok, check_in_id: check_in_id, duration: duration, monitor_config: monitor_config)
          ret
        end

        private

        def monitor_config_for(data)
          schedule = data["schedule"]
          return unless schedule.is_a?(Hash)

          cron_config = Sentry.configuration.cron
          options = { checkin_margin: cron_config.default_checkin_margin, max_runtime: cron_config.default_max_runtime }
          case schedule["type"].to_s
          when "crontab"
            Sentry::Cron::MonitorConfig.from_crontab(schedule["value"], timezone: data["timezone"], **options)
          when "interval"
            Sentry::Cron::MonitorConfig.from_interval(schedule["value"], schedule["unit"].to_sym, **options)
          end
        end
      end
    end
  end
end

Sentry.register_patch(:resque_scheduler) do |config|
  begin
    require "resque/scheduler"
  rescue LoadError
  end

  if defined?(::Resque::Scheduler) && defined?(::Rufus::Scheduler::RepeatJob)
    unless ::Resque::Job < Sentry::Resque::Scheduler::Job
      ::Resque::Job.prepend(Sentry::Resque::Scheduler::Job)
      ::Resque.singleton_class.prepend(Sentry::Resque::Scheduler::Push)
      ::Resque::Scheduler.singleton_class.prepend(Sentry::Resque::Scheduler::SchedulerPatch)
    end
  else
    config.sdk_logger.warn(Sentry::LOGGER_PROGNAME) { "You tried to enable the resque-scheduler integration but the `resque-scheduler` gem was not detected." }
  end
end
