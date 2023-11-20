# frozen_string_literal: true

return unless defined?(::SidekiqScheduler::Scheduler)

module Sentry
  module SidekiqScheduler
    module Scheduler
      def new_job(name, interval_type, config, schedule, options)
        # Schedule the job upstream first
        # SidekiqScheduler does not validate schedules
        # It will fail with an error if the schedule in the config is invalid.
        # If this errors out, let it fall through.
        rufus_job = super(name, interval_type, config, schedule, options)

        # Constantize the job class, and fail gracefully if it could not be found
        klass_const =
        begin
          config.fetch("class").constantize
        rescue NameError
          return rufus_job
        end

        monitor_config = Sentry::Cron::MonitorConfig.from_crontab(schedule)

        # only patch if not explicitly included in job by user
        unless klass_const.send(:ancestors).include?(Sentry::Cron::MonitorCheckIns)
          klass_const.send(:include, Sentry::Cron::MonitorCheckIns)
          klass_const.send(:sentry_monitor_check_ins,
                            slug: name,
                            monitor_config: monitor_config)
          
          ::Sidekiq.logger.info "Injected Sentry Crons monitor checkins into #{config.fetch("class")}"
        end

        return rufus_job
      end
    end
  end
end

Sentry.register_patch(:sidekiq_scheduler, Sentry::SidekiqScheduler::Scheduler, ::SidekiqScheduler::Scheduler)
