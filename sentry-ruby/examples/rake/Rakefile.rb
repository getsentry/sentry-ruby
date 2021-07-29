require "sentry-ruby"

Sentry.init do |config|
  config.dsn = 'https://2fb45f003d054a7ea47feb45898f7649@o447951.ingest.sentry.io/5434472'
end

# bundle exec rake raise_exception
task :raise_exception do
  1/0
end

# bundle exec rake send_message[foo]
task :send_message, ['name']  do |_task, args|
  Sentry.capture_message("message from #{args[:name]}")
end
