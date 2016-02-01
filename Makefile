# lol
VERSION := `grep '\d+\.\d+\.\d+' -o -E --color=never lib/raven/version.rb`

test:
	bundle install
	bundle exec rubocop
	bundle exec rake spec

release:
	gem build sentry-raven.gemspec
	gem push sentry-raven-${VERSION}.gem
