require 'logger'

module Raven
  module BreadcrumbLogger
    LEVELS = {
      ::Logger::DEBUG => 'debug',
      ::Logger::INFO  => 'info',
      ::Logger::WARN  => 'warn',
      ::Logger::ERROR => 'error',
      ::Logger::FATAL => 'fatal'
    }.freeze

    EXC_FORMAT = /^([a-zA-Z0-9]+)\:\s(.*)$/

    def self.parse_exception(message)
      lines = message.split(/\n\s*/)
      # TODO: wat
      return nil unless lines.length > 2

      match = lines[0].match(EXC_FORMAT)
      return nil unless match

      _, type, value = match.to_a
      [type, value]
    end

    def add(*args)
      add_breadcrumb(*args)
      super
    end

    def add_breadcrumb(severity, message = nil, progname = nil)
      message = progname if message.nil? # see Ruby's Logger docs for why
      return if ignored_logger?(progname)
      return if message.nil? || message == ""

      # some loggers will add leading/trailing space as they (incorrectly, mind you)
      # think of logging as a shortcut to std{out,err}
      message = message.to_s.strip

      last_crumb = Raven.breadcrumbs.peek
      # try to avoid dupes from logger broadcasts
      if last_crumb.nil? || last_crumb.message != message
        error = Raven::BreadcrumbLogger.parse_exception(message)
        # TODO(dcramer): we need to filter out the "currently captured error"
        if error
          Raven.breadcrumbs.record do |crumb|
            crumb.level = Raven::BreadcrumbLogger::LEVELS.fetch(severity, nil)
            crumb.category = progname || 'error'
            crumb.type = 'error'
            crumb.data = {
              :type => error[0],
              :value => error[1]
            }
          end
        else
          Raven.breadcrumbs.record do |crumb|
            crumb.level = Raven::BreadcrumbLogger::LEVELS.fetch(severity, nil)
            crumb.category = progname || 'logger'
            crumb.message = message
          end
        end
      end
    end

    private

    def ignored_logger?(progname)
      progname == "sentry" ||
        Raven.configuration.exclude_loggers.include?(progname)
    end
  end
  module OldBreadcrumbLogger
    def self.included(base)
      base.class_eval do
        include Raven::BreadcrumbLogger
        alias_method :add_without_raven, :add
        alias_method :add, :add_with_raven
      end
    end

    def add_with_raven(*args)
      add_breadcrumb(*args)
      add_without_raven(*args)
    end
  end
end

Raven.safely_prepend(
  "BreadcrumbLogger",
  :from => Raven,
  :to => ::Logger
)
