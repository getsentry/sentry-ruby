require 'sinatra'
require 'sentry-ruby'

Sentry.init do |config|
  config.dsn = 'https://2fb45f003d054a7ea47feb45898f7649@o447951.ingest.sentry.io/5434472'
  config.traces_sample_rate = 1.0
end

# this needs to be places before the CaptureException middleware
use Sentry::Rack::Tracing
use Sentry::Rack::CaptureException

get "/exception" do
  1/0
end
