module Sentry
  module Cron
    module MonitorCheckIns
      module Patch
        def perform(*args)
          slug = self.class.sentry_monitor_slug || self.class.name
          monitor_config = self.class.sentry_monitor_config

          check_in_id = Sentry.capture_check_in(slug,
                                                :in_progress,
                                                monitor_config: monitor_config)

          start = Sentry.utc_now.to_i
          ret = super
          duration = Sentry.utc_now.to_i - start

          Sentry.capture_check_in(slug,
                                  :ok,
                                  check_in_id: check_in_id,
                                  duration: duration,
                                  monitor_config: monitor_config)

          ret
        rescue Exception
          duration = Sentry.utc_now.to_i - start

          Sentry.capture_check_in(slug,
                                  :error,
                                  check_in_id: check_in_id,
                                  duration: duration,
                                  monitor_config: monitor_config)

          raise
        end
      end

      module ClassMethods
        def sentry_monitor_check_ins(slug: nil, monitor_config: nil)
          @sentry_monitor_slug = slug
          @sentry_monitor_config = monitor_config

          prepend Patch
        end

        def sentry_monitor_slug
          @sentry_monitor_slug
        end

        def sentry_monitor_config
          @sentry_monitor_config
        end
      end

      extend ClassMethods

      def self.included(base)
        base.extend(ClassMethods)
      end
    end
  end
end
