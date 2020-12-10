require 'benchmark/ips'
require 'benchmark/ipsa'
require 'raven'
require 'raven/breadcrumbs/logger'
require_relative 'application'

Raven.configure do |config|
  config.logger = Logger.new(nil)
  config.breadcrumbs_logger = [:active_support_logger]
  config.dsn = "dummy://12345:67890@sentry.localdomain:3000/sentry/42"
end

TestApp.configure do |config|
  config.middleware.delete ActionDispatch::DebugExceptions
  config.middleware.delete ActionDispatch::ShowExceptions
end

app.get("/exception")

report = MemoryProfiler.report do
  app.get("/exception")
end

report.pretty_print
