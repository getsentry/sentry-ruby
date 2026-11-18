# frozen_string_literal: true

module Sentry
  module Cron
    class Configuration
      # Defaults set here will apply to all {Cron::MonitorConfig} objects unless overwritten.

      # How long (in minutes) after the expected checkin time will we wait
      # until we consider the checkin to have been missed.
      # @return [Integer, nil]
      attr_accessor :default_checkin_margin

      # How long (in minutes) is the checkin allowed to run for in in_progress
      # before it is considered failed.
      # @return [Integer, nil]
      attr_accessor :default_max_runtime

      # tz database style timezone string
      # @return [String, nil]
      attr_accessor :default_timezone

      # How default (class-name-derived) cron monitor slugs are formatted.
      # Explicit `sentry_monitor_check_ins(slug: ...)` always wins over this.
      #
      # - +:mashed+ - CamelCase mashed to lowercase (`HappyWorker` -> `happyworker`)
      # - +:underscore+ - Rails-style word breaks (`HappyWorker` -> `happy_worker`)
      #
      # Only one format is active per process; check-ins are not dual-emitted.
      # @return [Symbol]
      attr_accessor :monitor_slug_format

      def initialize
        @monitor_slug_format = :mashed
      end
    end
  end
end
