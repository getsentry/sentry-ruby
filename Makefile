# lol
VERSION := `cat lib/raven/version.rb | grep -e 'VERSION =' | cut -c 14- | rev | cut -c 2- | rev`

test:
	bundle install
	bundle exec rake spec

release:
	gem build sentry-raven.gemspec
	gem push sentry-raven-${VERSION}.gem
