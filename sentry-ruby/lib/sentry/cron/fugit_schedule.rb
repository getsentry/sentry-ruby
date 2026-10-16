# frozen_string_literal: true

module Sentry
  module Cron
    # Converts fugit schedules into monitor configs. Returns nil for schedules
    # Sentry would read differently.
    module FugitSchedule
      class << self
        def from_cron(cron)
          crontab = crontab_for(cron)
          timezone = timezone_for(cron) if crontab
          MonitorConfig.from_crontab(crontab, timezone: timezone, **options) if timezone
        end

        def from_seconds(seconds)
          seconds = seconds.to_f
          return unless seconds > 0 && (seconds % 60).zero?

          seconds = seconds.to_i
          if (seconds % 86_400).zero?
            MonitorConfig.from_interval(seconds / 86_400, :day, **options)
          elsif (seconds % 3_600).zero?
            MonitorConfig.from_interval(seconds / 3_600, :hour, **options)
          else
            MonitorConfig.from_interval(seconds / 60, :minute, **options)
          end
        end

        private

        def options
          cron_config = Sentry.configuration.cron
          { checkin_margin: cron_config.default_checkin_margin, max_runtime: cron_config.default_max_runtime }
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
end
