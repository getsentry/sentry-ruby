# frozen_string_literal: true

module Sentry
  module Cron
    # Converts fugit schedules into monitor configs. Returns nil when the
    # schedule can't be expressed in the Crons schedule format.
    module FugitSchedule
      # `#n` and `#-1` (last) have Crons equivalents; other `#-n` don't.
      WEEKDAY_HASHES = [1, 2, 3, 4, 5, -1].freeze
      # et-orbi names offset zones like "+05:00".
      OFFSET = /\A([+-]\d{1,2}):?(\d{2})?\z/.freeze

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

        # Rebuilds a 5-field crontab from fugit's expanded fields. Returns nil for
        # sub-minute seconds, `%`, `&`, and negative days other than `L` and `#-1`.
        def crontab_for(cron)
          return unless defined?(::Fugit::Cron) && cron.is_a?(::Fugit::Cron)
          return unless cron.seconds&.size == 1
          return if cron.monthdays && cron.weekdays && cron.instance_variable_get(:@day_and)

          monthdays = monthday_field(cron.monthdays)
          weekdays = weekday_field(cron.weekdays)
          return unless monthdays && weekdays

          [
            crontab_field(cron.minutes, 0, 59, step: true),
            crontab_field(cron.hours, 0, 23, step: true),
            monthdays,
            crontab_field(cron.months, 1, 12, step: true),
            weekdays
          ].join(" ")
        end

        # Day fields never use `*/n`: Debian cron treats a field starting with
        # `*` as unrestricted when combining day-of-month and weekday.
        def monthday_field(monthdays)
          return "*" unless monthdays

          last, days = monthdays.partition(&:negative?)
          return unless last.all? { |day| day == -1 }

          fields = days.empty? ? [] : [crontab_field(days, 1, 31)]
          fields << "L" unless last.empty?
          fields.join(",")
        end

        def weekday_field(weekdays)
          return "*" unless weekdays

          days, hashed = weekdays.partition { |day| day.size == 1 }
          return unless hashed.all? { |_, hash| WEEKDAY_HASHES.include?(hash) }

          fields = days.empty? ? [] : [crontab_field(days.map(&:first), 0, 6)]
          hashed.each { |day, hash| fields << (hash == -1 ? "#{day}L" : "#{day}##{hash}") }
          fields.join(",")
        end

        def crontab_field(values, min, max, step: false)
          return "*" unless values

          if step && values.size > 1 && values.first == min
            increment = values[1] - values[0]
            return "*/#{increment}" if values == min.step(max, increment).to_a
          end

          values.chunk_while { |a, b| b == a + 1 }.map { |run| run.size > 1 ? "#{run.first}-#{run.last}" : run.first.to_s }.join(",")
        end

        # Sentry only accepts IANA names, so only whole-hour offsets get a zone.
        def timezone_for(cron)
          zone = cron.timezone || ::EtOrbi.determine_local_tzone
          return Sentry.configuration.cron.default_timezone unless zone

          offset = OFFSET.match(zone.name)
          offset ? offset_timezone(offset[1].to_i, offset[2].to_i) : ::TZInfo::Timezone.get(zone.name).identifier
        rescue StandardError
          nil
        end

        def offset_timezone(hours, minutes)
          return unless minutes.zero? && hours.between?(-12, 14)
          return "Etc/UTC" if hours.zero?

          # Etc/GMT signs are inverted: UTC+5 is Etc/GMT-5.
          "Etc/GMT#{hours.positive? ? "-" : "+"}#{hours.abs}"
        end
      end
    end
  end
end
