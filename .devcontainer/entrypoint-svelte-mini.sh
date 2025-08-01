#!/bin/bash
set -e

echo "Installing npm dependencies for Svelte mini..."

# Ensure proper ownership of workspace and node_modules directory
chown -R sentry:sentry /workspace/sentry
chown -R sentry:sentry /workspace/sentry/spec/apps/svelte-mini/node_modules

# Switch to sentry user and install npm dependencies
su - sentry -c "cd /workspace/sentry/spec/apps/svelte-mini && npm install"

# Switch to sentry user for the main command
exec su - sentry -c "cd /workspace/sentry/spec/apps/svelte-mini && exec $*"
