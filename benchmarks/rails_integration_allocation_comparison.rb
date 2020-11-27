require "benchmark/memory"
require 'raven'
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

Benchmark.memory do |x|
  x.report("master") { app.get("/exception") }
  x.report("branch") { app.get("/exception") }

  x.compare!
  x.hold!("/tmp/allocation_comparison.json")
end

