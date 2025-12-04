# frozen_string_literal: true

.PHONY: test
test:
	bundle exec rspec

.PHONY: lint
lint:
	bundle exec rubocop

.PHONY: install
install:
	bundle install

.PHONY: console
console:
	bundle exec bin/console

.PHONY: setup
setup:
	bundle install
	bundle exec bin/setup
