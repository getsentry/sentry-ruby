build:
	bundle install
	gem build sentry-sidekiq.gemspec

test:
	bundle exec rspec
	WITH_SENTRY_RAILS=1 bundle exec rspec spec/sentry/rails_spec.rb
