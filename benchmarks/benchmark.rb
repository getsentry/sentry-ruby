require 'benchmark/ips'
require 'raven'
require 'raven/breadcrumbs/logger'
require 'rack/test'
require_relative "../spec/support/test_rails_app/app"

def build_exception
  1 / 0
rescue ZeroDivisionError => exception
  exception
end

TestApp.configure do |config|
  config.middleware.delete ActionDispatch::DebugExceptions
  config.middleware.delete ActionDispatch::ShowExceptions
end

TestApp.initialize!
@app = Rack::MockRequest.new(TestApp)
RAILS_EXC = begin
  @app.get("/exception")
rescue => exc
  exc
end

DIVIDE_BY_ZERO = build_exception

Raven.configure do |config|
  config.logger = false
  config.dsn = "dummy://woopwoop"
end

LOGGER = Logger.new(nil)

Benchmark.ips do |x|
  x.config(:time => 5, :warmup => 2)

  x.report("simple") { Raven.capture_exception(DIVIDE_BY_ZERO) }
  x.report("rails") { Raven.capture_exception(RAILS_EXC) }
  x.report("lots o logs") do
    100.times { LOGGER.debug(rand(100_000).to_s) }
    Raven.capture_exception(DIVIDE_BY_ZERO)
  end

  x.compare!
end
