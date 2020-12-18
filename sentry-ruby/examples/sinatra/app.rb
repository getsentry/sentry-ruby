require 'sinatra'
require 'sentry-ruby'

Sentry.init do |config|
  config.dsn = 'https://2fb45f003d054a7ea47feb45898f7649@o447951.ingest.sentry.io/5434472'
  config.traces_sample_rate = 1.0
end

use Sentry::Rack::CaptureExceptions

get "/exception" do
  1/0
end
