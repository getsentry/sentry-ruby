# frozen_string_literal: true

module Sentry
  module Rails
    # Sends Crons check-ins for GoodJob cron entries.
    # Enable with `config.enabled_patches << :good_job_cron`.
    module GoodJobCron
      PAYLOAD_KEY = "_sentry_good_job_cron"

      module Job
        def serialize
          @_sentry_good_job_cron ||= Sentry::Rails::GoodJobCron.monitor_for(self)
          payload = super
          payload[PAYLOAD_KEY] = @_sentry_good_job_cron if @_sentry_good_job_cron
          payload
        end

        def deserialize(job_data)
          super
          @_sentry_good_job_cron = job_data[PAYLOAD_KEY]
          singleton_class.prepend(Perform) if @_sentry_good_job_cron
        end
      end

      module Perform
        def perform(*args, &block)
          Sentry::Rails::GoodJobCron.perform(self) { super(*args, &block) }
        end
        ruby2_keywords(:perform)
      end

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

        # GoodJob sets the cron key while an entry enqueues its job and clears it while jobs run.
        def monitor_for(job)
          key = ::GoodJob::CurrentThread.cron_key
          return unless key && Sentry.initialized?
          return if excluded?(key)

          entry = ::GoodJob::CronEntry.find(key)
          job_class = entry.job_class
          # A callable class can't be checked without calling it again.
          return unless job_class.respond_to?(:call) || job.class.name == job_class.to_s.delete_prefix("::")
          return if job.class < Sentry::Cron::MonitorCheckIns::Patch

          slug = Sentry::Cron::Slug.from(entry.key)
          return unless slug

          config = schedule_for(entry)
          unless config
            Sentry.sdk_logger.debug(Sentry::LOGGER_PROGNAME) { "Not monitoring GoodJob cron entry #{entry.key}: its schedule can't be expressed as a Crons schedule." }
            return
          end
          return if slug_shared?(entry.key, slug)

          { "slug" => slug, "crontab" => config.schedule.value, "timezone" => config.timezone }
        rescue StandardError => e
          Sentry.sdk_logger.error(Sentry::LOGGER_PROGNAME) { "Not monitoring GoodJob cron entry #{key}: #{e.class}: #{e.message}" }
          nil
        end

        def perform(job)
          data = job.instance_variable_get(:@_sentry_good_job_cron)
          return yield unless data && Sentry.initialized?

          cron_config = Sentry.configuration.cron
          monitor_config = Sentry::Cron::MonitorConfig.from_crontab(
            data["crontab"],
            timezone: data["timezone"],
            checkin_margin: cron_config.default_checkin_margin,
            max_runtime: cron_config.default_max_runtime
          )

          with_check_in(data["slug"], monitor_config) { yield }
        end

        def patch
          return if @patched

          @patched = true
          ActiveSupport.on_load(:active_job) do
            prepend Sentry::Rails::GoodJobCron::Job
          end
        end

        private

        def with_check_in(slug, monitor_config)
          check_in_id = Sentry.capture_check_in(slug, :in_progress, monitor_config: monitor_config)
          start = monotonic_now

          begin
            result = yield
            Sentry.capture_check_in(slug, :ok, check_in_id: check_in_id, duration: monotonic_now - start)
            result
          rescue Exception
            Sentry.capture_check_in(slug, :error, check_in_id: check_in_id, duration: monotonic_now - start)
            raise
          end
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
