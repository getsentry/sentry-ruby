test:
	bundle install
	bundle exec rake spec

release:
	# lol
	gem build sentry-raven.gemspec
	gem push sentry-raven-`cat lib/raven/version.rb | grep -e 'VERSION =' | cut -c 14-18 -`.gem
