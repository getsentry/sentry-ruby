# frozen_string_literal: true

module Sentry
  module Rails
    # Sends Crons check-ins for GoodJob cron entries.
    # Enable with `config.enabled_patches << :good_job_cron`.
    module GoodJobCron
      PAYLOAD_KEY = "_sentry_good_job_cron"
      CURRENT_ENTRY = :sentry_good_job_cron_entry

      module CronEntry
        def enqueue(*args)
          Thread.current[CURRENT_ENTRY] = self unless Sentry::Rails::GoodJobCron.excluded?(self)
          super
        ensure
          Thread.current[CURRENT_ENTRY] = nil
        end
      end

      module Job
        def serialize
          @_sentry_good_job_cron ||= Sentry::Rails::GoodJobCron.monitor_for(Thread.current[CURRENT_ENTRY], self)
          payload = super
          payload[PAYLOAD_KEY] = @_sentry_good_job_cron if @_sentry_good_job_cron
          payload
        end

        def deserialize(job_data)
          super
          @_sentry_good_job_cron = job_data[PAYLOAD_KEY]
        end
      end

      class << self
        def excluded?(entry)
          return false unless Sentry.initialized?

          key = entry.key.to_s
          Array(Sentry.configuration.rails.good_job_exclude_cron_jobs).any? do |pattern|
            (pattern.is_a?(Symbol) ? pattern.to_s : pattern) === key
          end
        rescue StandardError => e
          Sentry.sdk_logger.error(Sentry::LOGGER_PROGNAME) { "Could not check good_job_exclude_cron_jobs for #{entry.key}: #{e.class}: #{e.message}" }
          false
        end

        # Runs where GoodJob evaluates the schedule, so the time zone matches.
        def monitor_for(entry, job)
          return unless entry && Sentry.initialized?

          job_class = entry.job_class
          return unless job_class.respond_to?(:call) || job.class.name == job_class.to_s.delete_prefix("::")
          return if job.class < Sentry::Cron::MonitorCheckIns::Patch

          slug = Sentry::Cron::Slug.from(entry.key)
          return unless slug

          # Entries whose cron is a proc can change schedule between runs.
          cron = entry.params[:cron]
          config = Sentry::Cron::FugitSchedule.from_cron(::Fugit.parse(cron)) if cron.is_a?(String)
          return unless config

          { "slug" => slug, "crontab" => config.schedule.value, "timezone" => config.timezone }.compact
        rescue StandardError => e
          Sentry.sdk_logger.error(Sentry::LOGGER_PROGNAME) { "Not monitoring GoodJob cron entry #{entry.key}: #{e.class}: #{e.message}" }
          nil
        end

        def perform(job)
          data = job.instance_variable_get(:@_sentry_good_job_cron)
          return yield unless data && Sentry.initialized?

          slug = data["slug"]
          if data["crontab"]
            cron_config = Sentry.configuration.cron
            monitor_config = Sentry::Cron::MonitorConfig.from_crontab(
              data["crontab"],
              timezone: data["timezone"],
              checkin_margin: cron_config.default_checkin_margin,
              max_runtime: cron_config.default_max_runtime
            )
          end

          Sentry::Cron::MonitorCheckIns.with_check_in(slug, monitor_config: monitor_config) { yield }
        end

        def patch
          return if @patched

          @patched = true
          ActiveSupport.on_load(:active_job) do
            prepend Sentry::Rails::GoodJobCron::Job
            around_perform { |job, block| Sentry::Rails::GoodJobCron.perform(job, &block) }
          end

          apply = proc do
            # safe_constantize also loads it under the classic autoloader.
            entry_class = "GoodJob::CronEntry".safe_constantize
            if entry_class && !(entry_class < Sentry::Rails::GoodJobCron::CronEntry)
              entry_class.prepend(Sentry::Rails::GoodJobCron::CronEntry)
            end
          end
          ::Rails.application.reloader.to_prepare(&apply)
          apply.call if ::Rails.application.initialized?
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
