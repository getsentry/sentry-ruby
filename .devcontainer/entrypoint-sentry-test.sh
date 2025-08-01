#!/bin/bash
set -e

echo "Setting up sentry-test environment..."
cd /workspace/sentry

sudo chown -R sentry:sentry /workspace/sentry
git config --global --add safe.directory /workspace/sentry

# Only bundle install in the root folder for e2e test execution
echo "Installing bundle dependencies in root folder..."
bundle install

echo "✅ sentry-test setup completed!"

exec "$@"
