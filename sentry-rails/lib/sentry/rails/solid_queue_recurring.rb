# frozen_string_literal: true

module Sentry
  module Rails
    # Sends Crons check-ins for Solid Queue recurring tasks.
    # Enable with `config.enabled_patches << :solid_queue_recurring`.
    module SolidQueueRecurring
      PAYLOAD_KEY = "_sentry_recurring_task"
      CURRENT_TASK = :sentry_solid_queue_recurring_task

      module RecurringTask
        def enqueue(at:)
          Thread.current[CURRENT_TASK] = self unless Sentry::Rails::SolidQueueRecurring.excluded?(self)
          super
        ensure
          Thread.current[CURRENT_TASK] = nil
        end
      end

      module Job
        def serialize
          @_sentry_recurring_task ||= Sentry::Rails::SolidQueueRecurring.monitor_for(Thread.current[CURRENT_TASK], self)
          payload = super
          payload[PAYLOAD_KEY] = @_sentry_recurring_task if @_sentry_recurring_task
          payload
        end

        def deserialize(job_data)
          super
          @_sentry_recurring_task = job_data[PAYLOAD_KEY]
        end
      end

      class << self
        def excluded?(task)
          return false unless Sentry.initialized?

          Array(Sentry.configuration.rails.solid_queue_exclude_recurring_tasks).any? { |pattern| pattern === task.key.to_s }
        rescue StandardError => e
          Sentry.sdk_logger.error(Sentry::LOGGER_PROGNAME) { "Could not check solid_queue_exclude_recurring_tasks for #{task.key}: #{e.class}: #{e.message}" }
          false
        end

        # Runs in the scheduler, which is where Solid Queue evaluates the schedule.
        def monitor_for(task, job)
          return unless task && Sentry.initialized?
          job_class = task.class_name.present? ? task.class_name.safe_constantize : task.class.default_job_class
          return unless job.instance_of?(job_class)
          return if job_class < Sentry::Cron::MonitorCheckIns::Patch

          slug = Sentry::Cron::Slug.from(task.key)
          return unless slug

          config = Sentry::Cron::FugitSchedule.from_cron(cron_for(task))
          return unless config

          { "slug" => slug, "crontab" => config.schedule.value, "timezone" => config.timezone }.compact
        rescue StandardError => e
          Sentry.sdk_logger.error(Sentry::LOGGER_PROGNAME) { "Not monitoring Solid Queue recurring task #{task.key}: #{e.class}: #{e.message}" }
          nil
        end

        def perform(job)
          data = job.instance_variable_get(:@_sentry_recurring_task)
          return yield unless data && Sentry.initialized?

          return yield unless data["crontab"]

          cron_config = Sentry.configuration.cron
          monitor_config = Sentry::Cron::MonitorConfig.from_crontab(
            data["crontab"],
            timezone: data["timezone"],
            checkin_margin: cron_config.default_checkin_margin,
            max_runtime: cron_config.default_max_runtime
          )

          Sentry::Cron::MonitorCheckIns.with_check_in(data["slug"], monitor_config: monitor_config) { yield }
        end

        def patch
          return if @patched

          @patched = true
          ActiveSupport.on_load(:active_job) do
            prepend Sentry::Rails::SolidQueueRecurring::Job
            around_perform { |job, block| Sentry::Rails::SolidQueueRecurring.perform(job, &block) }
          end

          # Referencing RecurringTask loads Active Record and Active Job, so wait for it to be
          # loaded. The callback runs again after every code reload.
          ::Rails.autoloaders.main.on_load("SolidQueue::RecurringTask") { |klass, _| prepend_recurring_task(klass) }

          # The callback doesn't fire for a model that is already loaded.
          if defined?(::SolidQueue::RecurringTask) && !::SolidQueue.autoload?(:RecurringTask)
            prepend_recurring_task(::SolidQueue::RecurringTask)
          end
        end

        private

        def prepend_recurring_task(klass)
          klass.prepend(RecurringTask) unless klass < RecurringTask
        end

        # Mirrors RecurringTask, which applies SolidQueue.time_zone to zoneless schedules.
        def cron_for(task)
          cron = ::Fugit.parse(task.schedule)
          zone = ::SolidQueue.time_zone if ::SolidQueue.respond_to?(:time_zone)
          return cron unless cron.is_a?(::Fugit::Cron) && cron.zone.nil? && zone.present?

          ::Fugit.parse("#{cron.to_cron_s} #{zone}")
        end
      end
    end
  end
end

Sentry.register_patch(:solid_queue_recurring) do |config|
  if defined?(::SolidQueue) && defined?(::Rails.application) && ::Rails.application
    Sentry::Rails::SolidQueueRecurring.patch
  else
    config.sdk_logger.warn(Sentry::LOGGER_PROGNAME) { "You tried to enable the Solid Queue recurring task integration but the `solid_queue` gem was not detected." }
  end
end
