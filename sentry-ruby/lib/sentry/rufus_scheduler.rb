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
          # Run without rufus's rescue so the error is seen, then handle it like Job#do_call.
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
      # Returns [slug, monitor_config], or nil for jobs that aren't monitored (like `at`/`in`).
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

      # Job ids are random per process and block paths change between deploys,
      # so the slug comes from `name:`, then the handler method or class.
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
        case job
        when ::Rufus::Scheduler::CronJob
          Sentry::Cron::FugitSchedule.from_cron(job.cron_line)
        when ::Rufus::Scheduler::EveryJob
          Sentry::Cron::FugitSchedule.from_seconds(job.frequency)
        end
        # IntervalJob waits `interval` after each run ends, so it has no fixed
        # schedule to monitor against.
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
