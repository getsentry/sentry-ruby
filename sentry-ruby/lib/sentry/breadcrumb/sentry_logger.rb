require 'logger'

module Sentry
  class Breadcrumb
    module SentryLogger
      LEVELS = {
        ::Logger::DEBUG => 'debug',
        ::Logger::INFO => 'info',
        ::Logger::WARN => 'warn',
        ::Logger::ERROR => 'error',
        ::Logger::FATAL => 'fatal'
      }.freeze

      def add(*args, &block)
        super
        add_breadcrumb(*args, &block)
      end

      def add_breadcrumb(severity, message = nil, progname = nil)
        # because the breadcrumbs now belongs to different Hub's Scope in different threads
        # we need to make sure the current thread's Hub has been set before adding breadcrumbs
        return unless Sentry.get_current_hub

        category = "logger"

        # this is because the nature of Ruby Logger class:
        #
        # when given 1 argument, the argument will become both message and progname
        #
        # ```
        # logger.info("foo")
        # # message == progname == "foo"
        # ```
        #
        # and to specify progname with a different message,
        # we need to pass the progname as the argument and pass the message as a proc
        #
        # ```
        # logger.info("progname") { "the message" }
        # ```
        #
        # so the condition below is to replicate the similar behavior
        if message.nil?
          if block_given?
            message = yield
            category = progname
          else
            message = progname
          end
        end

        return if ignored_logger?(progname) || message.empty?

        # some loggers will add leading/trailing space as they (incorrectly, mind you)
        # think of logging as a shortcut to std{out,err}
        message = message.to_s.strip

        last_crumb = current_breadcrumbs.peek
        # try to avoid dupes from logger broadcasts
        if last_crumb.nil? || last_crumb.message != message
          current_breadcrumbs.record do |crumb|
            crumb.level = Sentry::Breadcrumb::SentryLogger::LEVELS.fetch(severity, nil)
            crumb.category = category
            crumb.message = message
            crumb.type =
              if severity >= 3
                "error"
              else
                crumb.level
              end
          end
        end
      end

      private

      def ignored_logger?(progname)
        progname == LOGGER_PROGNAME ||
          Sentry.configuration.exclude_loggers.include?(progname)
      end

      def current_breadcrumbs
        Sentry.breadcrumbs
      end
    end
  end
end

::Logger.send(:prepend, Sentry::Breadcrumb::SentryLogger)
