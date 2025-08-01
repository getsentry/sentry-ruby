#!/bin/bash
set -e

echo "Installing Ruby dependencies for Rails mini..."

# Ensure proper ownership of workspace
chown -R sentry:sentry /workspace/sentry

# Switch to sentry user and run bundle install commands
su - sentry -c "cd /workspace/sentry && bundle install --gemfile=sentry-ruby/Gemfile"
su - sentry -c "cd /workspace/sentry && bundle install --gemfile=sentry-rails/Gemfile"

# Change to the rails-mini app directory and switch to sentry user
cd /workspace/sentry/spec/apps/rails-mini

# Switch to sentry user for the main command
exec su - sentry -c "cd /workspace/sentry/spec/apps/rails-mini && exec $*"
