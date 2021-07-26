require "rake"
require "sentry-ruby"

Sentry.init do |config|
  config.dsn = 'http://12345:67890@sentry.localdomain/sentry/42'
  config.background_worker_threads = 0
end

task :raise_exception do
  1/0
end

task :raise_exception_without_rake_integration do
  Sentry.configuration.skip_rake_integration = true
  1/0
end

task :pass_arguments, ['name']  do |_task, args|
  puts args[:name]
end
