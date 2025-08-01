#!/bin/bash
set -e

echo "Installing npm dependencies for Svelte mini..."

# Ensure proper ownership of node_modules directory
sudo chown -R sentry:sentry /workspace/sentry/spec/apps/svelte-mini/node_modules

# Install npm dependencies
cd /workspace/sentry/spec/apps/svelte-mini
npm install

exec "$@"
