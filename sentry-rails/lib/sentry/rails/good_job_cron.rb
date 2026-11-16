# frozen_string_literal: true

module Sentry
  module Rails
    # Sends Crons check-ins for GoodJob cron entries.
    # Enable with `config.enabled_patches << :good_job_cron`.
    module GoodJobCron
      EVENT_STATE = :sentry_good_job_cron

      class << self
        def excluded?(key)
          return false unless Sentry.initialized?

          key = key.to_s
          Array(Sentry.configuration.rails.good_job_exclude_cron_jobs).any? do |pattern|
            (pattern.is_a?(Symbol) ? pattern.to_s : pattern) === key
          end
        rescue StandardError => e
          Sentry.sdk_logger.error(Sentry::LOGGER_PROGNAME) { "Could not check good_job_exclude_cron_jobs for #{key}: #{e.class}: #{e.message}" }
          false
        end

        # The persisted record identifies the cron run, including retries and callable classes.
        def monitor_for(job)
          key = job.cron_key
          return unless key && Sentry.initialized?
          return if excluded?(key)

          entry = ::GoodJob::CronEntry.find(key)
          job_class = job.job_class.safe_constantize
          return if job_class && job_class < Sentry::Cron::MonitorCheckIns::Patch

          slug = Sentry::Cron::Slug.from(entry.key)
          return unless slug

          config = schedule_for(entry)
          unless config
            Sentry.sdk_logger.debug(Sentry::LOGGER_PROGNAME) { "Not monitoring GoodJob cron entry #{entry.key}: its schedule can't be expressed as a Crons schedule." }
            return
          end
          return if slug_shared?(entry.key, slug)

          [slug, config]
        rescue StandardError => e
          Sentry.sdk_logger.error(Sentry::LOGGER_PROGNAME) { "Not monitoring GoodJob cron entry #{key}: #{e.class}: #{e.message}" }
          nil
        end

        # Evented subscribers receive start before execution and finish afterwards.
        # State belongs to the notification payload, so nested and concurrent runs are independent.
        def start(_name, _id, payload)
          return unless Sentry.initialized? && Sentry.configuration.enabled_patches.include?(:good_job_cron)

          monitor = monitor_for(payload[:job])
          return unless monitor

          slug, schedule = monitor
          cron_config = Sentry.configuration.cron
          config = Sentry::Cron::MonitorConfig.from_crontab(
            schedule.schedule.value,
            timezone: schedule.timezone,
            checkin_margin: cron_config.default_checkin_margin,
            max_runtime: cron_config.default_max_runtime
          )
          check_in_id = Sentry.capture_check_in(slug, :in_progress, monitor_config: config)
          payload[EVENT_STATE] = { slug: slug, check_in_id: check_in_id, started_at: monotonic_now }
        rescue StandardError => e
          log_error(e)
        end

        def finish(_name, _id, payload)
          state = payload.delete(EVENT_STATE)
          return unless state && Sentry.initialized?

          error = payload[:handled_error] || payload[:unhandled_error] || payload[:error] || payload[:exception]
          Sentry.capture_check_in(
            state[:slug], error ? :error : :ok,
            check_in_id: state[:check_in_id], duration: monotonic_now - state[:started_at]
          )
        rescue StandardError => e
          log_error(e)
        end

        def patch
          return if @subscriber

          @subscriber = ActiveSupport::Notifications.subscribe("perform_job.good_job", self)
        end

        private

        def log_error(error)
          Sentry.sdk_logger.error(Sentry::LOGGER_PROGNAME) { "Could not send GoodJob cron check-in: #{error.class}: #{error.message}" }
        end

        def monotonic_now
          Process.clock_gettime(Process::CLOCK_MONOTONIC)
        end

        # Entries whose cron is a proc can change schedule between runs. GoodJob's
        # scheduler threads read zoneless schedules in the app's time zone, which
        # an enqueue from a request using Time.use_zone wouldn't see.
        def schedule_for(entry)
          cron = entry.params[:cron]
          return unless cron.is_a?(String)

          Time.use_zone(Time.zone_default) { Sentry::Cron::FugitSchedule.from_cron(::Fugit.parse(cron)) }
        end

        # Different keys can share a slug, like long keys cut at the same length.
        # One monitor can't follow two schedules, so none of them are monitored.
        def slug_shared?(key, slug)
          colliding = ::GoodJob::CronEntry.all.select do |other|
            other.key.to_s != key.to_s && Sentry::Cron::Slug.from(other.key) == slug && monitored?(other)
          end.map(&:key)
          return false if colliding.empty?

          @slug_warnings ||= Concurrent::Map.new
          if @slug_warnings.put_if_absent(key.to_s, true).nil?
            Sentry.sdk_logger.warn(Sentry::LOGGER_PROGNAME) do
              "Not monitoring GoodJob cron entry #{key}: its monitor slug #{slug} is also used by #{colliding.join(", ")}. Rename or exclude one of them."
            end
          end
          true
        end

        def monitored?(entry)
          return false if excluded?(entry.key) || !schedule_for(entry)

          job_class = entry.job_class
          job_class = job_class.safe_constantize if job_class.is_a?(String)
          !(job_class.is_a?(Class) && job_class < Sentry::Cron::MonitorCheckIns::Patch)
        end
      end
    end
  end
end

Sentry.register_patch(:good_job_cron) do |config|
  if defined?(::GoodJob) && defined?(::Rails.application) && ::Rails.application
    Sentry::Rails::GoodJobCron.patch
  else
    config.sdk_logger.warn(Sentry::LOGGER_PROGNAME) { "You tried to enable the GoodJob cron integration but the `good_job` gem was not detected." }
  end
end
