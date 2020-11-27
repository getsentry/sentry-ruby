require 'benchmark/memory'
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

Benchmark.memory do |x|
  x.report("master") { Sentry.capture_exception(exception) }
  x.report("branch") { Sentry.capture_exception(exception) }

  x.compare!
  x.hold!("/tmp/allocation_comparison.json")
end
