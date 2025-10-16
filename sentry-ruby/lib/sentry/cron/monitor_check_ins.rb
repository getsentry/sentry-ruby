# frozen_string_literal: true

module Sentry
  module Cron
    module MonitorCheckIns
      MAX_SLUG_LENGTH = 50
      MAX_NAME_LENGTH = 128
      SLUG_HASH_LENGTH = 10

      module Patch
        def perform(*args, **opts)
          slug = self.class.sentry_monitor_slug
          monitor_config = self.class.sentry_monitor_config

          check_in_id = Sentry.capture_check_in(slug,
                                                :in_progress,
                                                monitor_config: monitor_config)

          start = Metrics::Timing.duration_start

          begin
            # need to do this on ruby <= 2.6 sadly
            ret = method(:perform).super_method.arity == 0 ? super() : super
            duration = Metrics::Timing.duration_end(start)

            Sentry.capture_check_in(slug,
                                    :ok,
                                    check_in_id: check_in_id,
                                    duration: duration,
                                    monitor_config: monitor_config)

            ret
          rescue Exception
            duration = Metrics::Timing.duration_end(start)

            Sentry.capture_check_in(slug,
                                    :error,
                                    check_in_id: check_in_id,
                                    duration: duration,
                                    monitor_config: monitor_config)

            raise
          end
        end
      end

      module ClassMethods
        def sentry_monitor_check_ins(slug: nil, monitor_config: nil)
          if monitor_config && Sentry.configuration
            cron_config = Sentry.configuration.cron
            monitor_config.checkin_margin ||= cron_config.default_checkin_margin
            monitor_config.max_runtime ||= cron_config.default_max_runtime
            monitor_config.timezone ||= cron_config.default_timezone
          end

          @sentry_monitor_slug = slug
          @sentry_monitor_config = monitor_config

          prepend Patch
        end

        def sentry_monitor_slug(name: self.name)
          @sentry_monitor_slug ||= begin
            slug = name.gsub("::", "-").gsub(/([A-Z]+)([A-Z][a-z])/, '\1_\2').gsub(/([a-z\d])([A-Z])/, '\1_\2').downcase
            if slug.length > MAX_SLUG_LENGTH
              diff_length = slug.length + 1 + SLUG_HASH_LENGTH - MAX_SLUG_LENGTH
              trim_part = ""
              slug.scan(/([^_-]+)([_-])/) do |match, separator|
                trim_part = "#{trim_part}#{match}#{separator}"
                break if trim_part.length >= diff_length
              end
              trim_part = slug[0...diff_length] if trim_part.empty?
              hash = OpenSSL::Digest::SHA256.hexdigest(trim_part)[0..SLUG_HASH_LENGTH-1]
              slug = "#{hash}_#{slug.sub(trim_part, '')}"
            end
            slug
          end
        end

        def sentry_monitor_config
          @sentry_monitor_config
        end
      end

      def self.included(base)
        base.extend(ClassMethods)
      end
    end
  end
end
