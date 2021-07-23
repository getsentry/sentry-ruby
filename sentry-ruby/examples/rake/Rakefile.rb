require "sentry-ruby"

Sentry.init do |config|
  config.dsn = 'https://2fb45f003d054a7ea47feb45898f7649@o447951.ingest.sentry.io/5434472'
end

task :raise_exception do
  1/0
end

task :send_message do
  Sentry.capture_message("message from rake")
end
