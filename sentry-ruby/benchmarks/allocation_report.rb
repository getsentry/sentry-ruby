require 'benchmark/ipsa'
require "sentry-ruby"
require "sentry/benchmarks/benchmark_transport"

Sentry.init do |config|
  config.logger = ::Logger.new(nil)
  config.dsn = "dummy://12345:67890@sentry.localdomain:3000/sentry/42"
  config.transport.transport_class = Sentry::BenchmarkTransport
  config.breadcrumbs_logger = [:sentry_logger]
end

exception = begin
              1/0
            rescue => exp
              exp
            end

Sentry.capture_exception(exception)

report = MemoryProfiler.report do
  Sentry.capture_exception(exception)
end

report.pretty_print
