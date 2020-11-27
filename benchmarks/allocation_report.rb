require 'benchmark/ips'
require 'benchmark/ipsa'
require 'sentry-raven-without-integrations'

Raven.configure do |config|
  config.logger = Logger.new(nil)
  config.dsn = "dummy://12345:67890@sentry.localdomain:3000/sentry/42"
end

exception = begin
              1/0
            rescue => e
              e
            end

Raven.capture_exception(exception)

report = MemoryProfiler.report do
  Raven.capture_exception(exception)
end

report.pretty_print
