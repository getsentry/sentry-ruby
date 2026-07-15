#!/usr/bin/env bash
#
# Installs the sentry-ruby toolchain.
#
set -euo pipefail

RUBY_VERSION="${RUBYVERSION:-latest}"
USERNAME="${_REMOTE_USER:-sentry}"
USER_HOME="${_REMOTE_USER_HOME:-/home/${USERNAME}}"

echo "📦 Installing Chromium and ChromeDriver..."
echo "deb http://deb.debian.org/debian sid main" > /etc/apt/sources.list.d/debian.list
wget -qO- https://ftp-master.debian.org/keys/archive-key-12.asc \
  | gpg --dearmor > /etc/apt/trusted.gpg.d/debian-archive-keyring.gpg
wget -qO- https://ftp-master.debian.org/keys/archive-key-12-security.asc \
  | gpg --dearmor > /etc/apt/trusted.gpg.d/debian-archive-security-keyring.gpg
for directory in bin lib lib32 lib64 libo32 libx32 sbin; do
  dpkg-divert --package base-files --no-rename --remove "/${directory}"
done
apt-get update
apt-get install -y --no-install-recommends chromium chromium-driver
rm -rf /var/lib/apt/lists/* /var/cache/apt/* /etc/apt/sources.list.d/debian.list

MISE_BIN="$(command -v mise || echo /usr/local/bin/mise)"
"$MISE_BIN" --version

# Activate mise for the remote user's interactive shells.
echo "eval \"\$(${MISE_BIN} activate bash)\"" >> "${USER_HOME}/.bashrc"
echo "eval \"\$(${MISE_BIN} activate zsh)\"" >> "${USER_HOME}/.zshenv"
chown "${USERNAME}:${USERNAME}" "${USER_HOME}/.bashrc" "${USER_HOME}/.zshenv"

# Feature installers run as root, but the toolchain belongs to the remote user.
as_user() {
  sudo -u "${USERNAME}" -H env "PATH=${USER_HOME}/.local/bin:/usr/local/bin:/usr/bin:/bin" "$@"
}

echo "📦 Pre-installing toolchain..."
as_user env MISE_RUBY_COMPILE=0 "$MISE_BIN" install \
  "java@temurin-21" \
  "ruby@${RUBY_VERSION}" \
  "node@lts"

echo "✅ Toolchain pre-install completed!"
