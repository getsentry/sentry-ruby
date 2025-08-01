#!/bin/bash
set -e

echo "Installing Ruby dependencies for Rails mini..."
cd /workspace/sentry

# Install dependencies for sentry-ruby and sentry-rails
bundle install --gemfile=sentry-ruby/Gemfile
bundle install --gemfile=sentry-rails/Gemfile

# Change to the rails-mini app directory
cd /workspace/sentry/spec/apps/rails-mini

exec "$@"
