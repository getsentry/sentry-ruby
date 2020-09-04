require 'benchmark/ips'
require 'benchmark/ipsa'
require 'raven'
require 'raven/breadcrumbs/logger'
require 'raven/transports/dummy'
require_relative "../spec/support/test_rails_app/app"

TestApp.configure do |config|
  config.middleware.delete ActionDispatch::DebugExceptions
  config.middleware.delete ActionDispatch::ShowExceptions
end

Raven.configure do |config|
  config.logger = Logger.new(nil)
  config.dsn = "dummy://12345:67890@sentry.localdomain:3000/sentry/42"
end

@app = make_basic_app
RAILS_EXC = begin
  @app.get("/exception")
rescue => exc
  exc
end

Raven.capture_exception(RAILS_EXC) # fire it once to get one-time stuff out of rpt

report = MemoryProfiler.report do
  Raven.capture_exception(RAILS_EXC)
end

report.pretty_print
