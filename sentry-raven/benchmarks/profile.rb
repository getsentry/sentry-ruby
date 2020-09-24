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

require 'ruby-prof'

RubyProf.measure_mode = RubyProf::PROCESS_TIME

# profile the code
result = RubyProf.profile do
  100.times { Raven.capture_exception(RAILS_EXC) }
end

# print a graph profile to text
printer = RubyProf::MultiPrinter.new(result)
printer.print(:path => "./tmp", :profile => "profile")
