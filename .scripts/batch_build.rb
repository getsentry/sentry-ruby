INTEGRATIONS = %w(sentry-rails sentry-sidekiq sentry-delayed_job sentry-resque)
GEMS = %w(sentry-ruby) + INTEGRATIONS

GEMS.each do |gem_name|
  puts(`cd #{gem_name}; make build`)
end
