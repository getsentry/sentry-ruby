# frozen_string_literal: true

module Sentry
  # Sends Crons check-ins for rufus-scheduler `cron`, `every` and `interval` jobs.
  # Enable with `config.enabled_patches << :rufus_scheduler`.
  module RufusScheduler
    module Job
      protected

      def do_call(time, do_rescue)
        return super unless Sentry.initialized? && (monitor = sentry_monitor)

        slug, monitor_config = monitor
        check_in_id = Sentry.capture_check_in(slug, :in_progress, monitor_config: monitor_config)
        start = Process.clock_gettime(Process::CLOCK_MONOTONIC)

        begin
          # Rescue here instead of inside rufus so the error is seen; the
          # rescue below mirrors Rufus::Scheduler::Job#do_call.
          ret = super(time, false)
        rescue Exception => e
          duration = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start
          Sentry.capture_check_in(slug, :error, check_in_id: check_in_id, duration: duration, monitor_config: monitor_config)

          raise unless do_rescue && e.is_a?(StandardError)
          return if e.is_a?(::Rufus::Scheduler::Job::KillSignal)

          return @scheduler.on_error(self, e)
        end

        duration = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start
        Sentry.capture_check_in(slug, :ok, check_in_id: check_in_id, duration: duration, monitor_config: monitor_config)

        ret
      end

      private

      def sentry_monitor
        return @sentry_monitor if defined?(@sentry_monitor)

        @sentry_monitor = Sentry::RufusScheduler.monitor_for(self)
      rescue StandardError => e
        Sentry.sdk_logger.error(Sentry::LOGGER_PROGNAME) { "Not monitoring rufus-scheduler job #{id}: #{e.class}: #{e.message}" }
        @sentry_monitor = nil
      end
    end

    MAX_SLUG_LENGTH = 50

    class << self
      # Returns [slug, monitor_config] for repeating jobs, nil for jobs that
      # are not monitored. one-off (`at`/`in`) jobs are never monitored.
      def monitor_for(job)
        return unless job.is_a?(::Rufus::Scheduler::RepeatJob)
        return if job.opts[:sentry_monitor] == false
        return if sidekiq_scheduler_job?(job)

        slug = slug_for(job)
        unless slug
          Sentry.sdk_logger.warn(Sentry::LOGGER_PROGNAME) do
            "Not monitoring rufus-scheduler job #{job.id} at #{job.source_location&.join(":")}: " \
              "pass `name:` to give it a stable monitor slug."
          end
          return
        end

        [slug, monitor_config_for(job)]
      end

      private

      # sidekiq-scheduler jobs are monitored by the :sidekiq_scheduler patch.
      def sidekiq_scheduler_job?(job)
        file, _ = job.callable.source_location if job.callable.respond_to?(:source_location)
        file&.end_with?("sidekiq-scheduler/scheduler.rb")
      end

      # Job ids are random per process, so the slug comes from the `name:` option,
      # then the handler method or class. Blocks have no stable name: their file
      # path can change on every deploy.
      def slug_for(job)
        handler = job.handler
        source =
          if job.name
            job.name.to_s
          elsif handler.is_a?(Method)
            owner = handler.receiver.is_a?(Module) ? handler.receiver : handler.owner
            [owner == Object ? nil : owner.name, handler.name].compact.join("::")
          elsif !handler.is_a?(Proc)
            handler.class.name
          end
        return unless source

        slug = source.downcase.gsub(/[^a-z0-9_-]+/, "-").gsub(/\A-+|-+\z/, "")
        slug = slug[0, MAX_SLUG_LENGTH].delete_suffix("-")
        slug.empty? ? nil : slug
      end

      def monitor_config_for(job)
        cron_config = Sentry.configuration.cron
        options = { checkin_margin: cron_config.default_checkin_margin, max_runtime: cron_config.default_max_runtime }

        case job
        when ::Rufus::Scheduler::CronJob
          crontab = crontab_for(job.cron_line)
          timezone = timezone_for(job.cron_line)
          Sentry::Cron::MonitorConfig.from_crontab(crontab, timezone: timezone, **options) if crontab && timezone
        when ::Rufus::Scheduler::EveryJob
          interval_for(job.frequency, options)
        end
        # IntervalJob waits `interval` after each run ends, so it has no fixed
        # schedule to monitor against.
      end

      def interval_for(seconds, options)
        seconds = seconds.to_f
        return unless seconds > 0 && (seconds % 60).zero?

        seconds = seconds.to_i
        if (seconds % 86_400).zero?
          Sentry::Cron::MonitorConfig.from_interval(seconds / 86_400, :day, **options)
        elsif (seconds % 3_600).zero?
          Sentry::Cron::MonitorConfig.from_interval(seconds / 3_600, :hour, **options)
        else
          Sentry::Cron::MonitorConfig.from_interval(seconds / 60, :minute, **options)
        end
      end

      # Rebuilds a 5-field crontab from fugit's expanded fields so Sentry
      # (Debian cron rules) reads it the same way. Returns nil for fugit-only
      # syntax: sub-minute seconds, `L`, `#`, `%` and `&`.
      def crontab_for(cron)
        return unless defined?(::Fugit::Cron) && cron.is_a?(::Fugit::Cron)
        return unless cron.seconds&.size == 1
        return if cron.monthdays&.any?(&:negative?)
        return if cron.weekdays&.any? { |day| day.size > 1 }
        return if cron.monthdays && cron.weekdays && cron.instance_variable_get(:@day_and)

        [
          crontab_field(cron.minutes, 0, 59, step: true),
          crontab_field(cron.hours, 0, 23, step: true),
          # Day fields never use `*/n`: Debian cron treats a field starting
          # with `*` as unrestricted when combining day-of-month and weekday.
          crontab_field(cron.monthdays, 1, 31),
          crontab_field(cron.months, 1, 12, step: true),
          crontab_field(cron.weekdays&.map(&:first), 0, 6)
        ].join(" ")
      end

      def crontab_field(values, min, max, step: false)
        return "*" unless values

        if step && values.size > 1 && values.first == min
          increment = values[1] - values[0]
          return "*/#{increment}" if values == min.step(max, increment).to_a
        end

        values.chunk_while { |a, b| b == a + 1 }.map { |run| run.size > 1 ? "#{run.first}-#{run.last}" : run.first.to_s }.join(",")
      end

      # Sentry only accepts IANA names, so offsets such as "+05:30" get no config.
      def timezone_for(cron)
        zone = cron.timezone || ::EtOrbi.determine_local_tzone
        return Sentry.configuration.cron.default_timezone unless zone

        ::TZInfo::Timezone.get(zone.name).identifier
      rescue StandardError
        nil
      end
    end
  end
end

Sentry.register_patch(:rufus_scheduler) do |config|
  if defined?(::Rufus::Scheduler::RepeatJob)
    ::Rufus::Scheduler::Job.prepend(Sentry::RufusScheduler::Job) unless ::Rufus::Scheduler::Job.ancestors.include?(Sentry::RufusScheduler::Job)
  else
    config.sdk_logger.warn(Sentry::LOGGER_PROGNAME) { "You tried to enable the rufus-scheduler integration but the `rufus-scheduler` gem was not detected." }
  end
end
