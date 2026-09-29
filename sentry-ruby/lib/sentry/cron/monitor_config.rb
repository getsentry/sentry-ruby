# frozen_string_literal: true

require "sentry/cron/monitor_schedule"

module Sentry
  module Cron
    class MonitorConfig
      # The monitor schedule configuration
      # @return [MonitorSchedule::Crontab, MonitorSchedule::Interval]
      attr_accessor :schedule

      # How long (in minutes) after the expected checkin time will we wait
      # until we consider the checkin to have been missed.
      # @return [Integer, nil]
      attr_accessor :checkin_margin

      # How long (in minutes) is the checkin allowed to run for in in_progress
      # before it is considered failed.
      # @return [Integer, nil]
      attr_accessor :max_runtime

      # How many consecutive failed check-ins it takes to create an issue.
      # @return [Integer, nil]
      attr_accessor :failure_issue_threshold

      # How many consecutive OK check-ins it takes to resolve an issue.
      # @return [Integer, nil]
      attr_accessor :recovery_threshold

      # tz database style timezone string
      # @return [String, nil]
      attr_accessor :timezone

      def initialize(schedule, checkin_margin: nil, max_runtime: nil, failure_issue_threshold: nil, recovery_threshold: nil, timezone: nil)
        @schedule = schedule
        @checkin_margin = checkin_margin
        @max_runtime = max_runtime
        @failure_issue_threshold = failure_issue_threshold
        @recovery_threshold = recovery_threshold
        @timezone = timezone
      end

      def self.from_crontab(crontab, **options)
        new(MonitorSchedule::Crontab.new(crontab), **options)
      end

      def self.from_interval(num, unit, **options)
        return nil unless MonitorSchedule::Interval::VALID_UNITS.include?(unit)

        new(MonitorSchedule::Interval.new(num, unit), **options)
      end

      def to_h
        {
          schedule: schedule.to_h,
          checkin_margin: checkin_margin,
          max_runtime: max_runtime,
          failure_issue_threshold: failure_issue_threshold,
          recovery_threshold: recovery_threshold,
          timezone: timezone
        }.compact
      end
    end
  end
end
