require 'raven'
require_relative 'application'

TestApp.configure do |config|
  config.middleware.delete ActionDispatch::DebugExceptions
  config.middleware.delete ActionDispatch::ShowExceptions
end

Raven.configure do |config|
  config.logger = Logger.new(nil)
  config.breadcrumbs_logger = [:active_support_logger]
  config.dsn = "dummy://12345:67890@sentry.localdomain:3000/sentry/42"
end

require 'ruby-prof'

RubyProf.measure_mode = RubyProf::PROCESS_TIME

# profile the code
result = RubyProf.profile do
  100.times { app.get("/exception") }
end

# print a graph profile to text
printer = RubyProf::MultiPrinter.new(result)
printer.print(:path => "./tmp", :profile => "profile")
