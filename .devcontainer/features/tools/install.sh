#!/usr/bin/env bash
#
# Installs mise system-wide and pre-installs the sentry-ruby toolchain (Java,
# Ruby, Node) plus a headless Chromium, all baked into the image so the
# container starts without downloading anything at runtime.
#
set -euo pipefail

RUBY_VERSION="${RUBYVERSION:-latest}"
USERNAME="${_REMOTE_USER:-sentry}"
USER_HOME="${_REMOTE_USER_HOME:-/home/${USERNAME}}"

# Install mise system-wide via the official installer. This downloads a prebuilt
# binary from mise's CDN rather than the GitHub API, avoiding the API rate
# limits the gh-release-based community feature hits on shared CI runners.
echo "📦 Installing mise..."
export MISE_INSTALL_PATH=/usr/local/bin/mise
curl https://mise.run | sh
MISE_BIN=/usr/local/bin/mise
"$MISE_BIN" --version

# Activate mise for the remote user's interactive shells.
echo "eval \"\$(${MISE_BIN} activate bash)\"" >> "${USER_HOME}/.bashrc"
echo "eval \"\$(${MISE_BIN} activate zsh)\"" >> "${USER_HOME}/.zshenv"
chown "${USERNAME}:${USERNAME}" "${USER_HOME}/.bashrc" "${USER_HOME}/.zshenv"

# Run a command as the remote user with a sane PATH so mise writes tools into
# the user's own data dir (~/.local/share/mise) rather than root's.
as_user() {
  sudo -u "${USERNAME}" -H env "PATH=${USER_HOME}/.local/bin:/usr/local/bin:/usr/bin:/bin" "$@"
}

# ~/.local/bin is on PATH but nothing creates it now that mise is installed
# system-wide; ensure it exists for the Chromium symlink below.
as_user mkdir -p "${USER_HOME}/.local/bin"

# Java is always installed (required for JRuby) and listed in .mise.toml so it
# is available regardless of which Ruby flavour is used.
echo "📦 Pre-installing java@temurin-21..."
as_user "$MISE_BIN" install "java@temurin-21"
as_user "$MISE_BIN" use --global "java@temurin-21"

# Pre-install Ruby (precompiled) so the container starts immediately.
echo "📦 Pre-installing ruby@${RUBY_VERSION} (precompiled)..."
as_user env MISE_RUBY_COMPILE=0 "$MISE_BIN" install "ruby@${RUBY_VERSION}"
as_user "$MISE_BIN" use --global "ruby@${RUBY_VERSION}"

# Node.js is always needed for the svelte-mini e2e app.
echo "📦 Pre-installing node@lts..."
as_user "$MISE_BIN" install "node@lts"
as_user "$MISE_BIN" use --global "node@lts"

# Install headless Chromium via Playwright (includes all system dependencies)
# and symlink the binary into ~/.local/bin which is already on PATH.
echo "📦 Installing headless Chromium via Playwright..."
as_user "${USER_HOME}/.local/share/mise/shims/npx" playwright install chromium --with-deps --only-shell
# Playwright lays out the binary under chrome-linux/ on arm64 and chrome-linux64/
# on x86_64 (since Playwright 1.57), so the glob has to match both.
as_user bash -c "ln -sf ${USER_HOME}/.cache/ms-playwright/chromium-*/chrome-linux*/chrome ${USER_HOME}/.local/bin/chromium"

echo "✅ Toolchain pre-install completed!"
