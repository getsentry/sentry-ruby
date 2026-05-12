ARG BASE_IMAGE=ubuntu:24.04
FROM ${BASE_IMAGE}

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
  sudo \
  gnupg \
  git \
  curl \
  wget \
  ca-certificates \
  build-essential \
  pkg-config \
  libssl-dev \
  libreadline-dev \
  zlib1g-dev \
  autoconf \
  bison \
  libyaml-dev \
  libncurses5-dev \
  libffi-dev \
  libgdbm-dev \
  sqlite3 \
  libsqlite3-dev \
  tzdata \
  && apt-get clean \
  && rm -rf /var/lib/apt/lists/*

RUN echo "sentry ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/sentry \
  && chmod 0440 /etc/sudoers.d/sentry

RUN userdel -r ubuntu 2>/dev/null || true \
  && groupdel ubuntu 2>/dev/null || true \
  && groupadd --gid 1000 sentry \
  && useradd --uid 1000 --gid sentry --shell /bin/bash --create-home sentry

WORKDIR /workspace/sentry

RUN chown -R sentry:sentry /workspace/sentry

ENV LANG=C.UTF-8 \
  BUNDLE_JOBS=4 \
  BUNDLE_RETRY=3 \
  REDIS_HOST=redis \
  PATH=/home/sentry/.local/share/mise/shims:/home/sentry/.local/bin:$PATH

USER sentry

# Pre-create the bundle directory owned by sentry so that a Docker named volume
# mounted here is initialised with the correct ownership (Docker copies image
# directory content when a volume is first attached).
RUN mkdir -p /home/sentry/bundle

RUN curl https://mise.run | sh \
  && echo 'eval "$(/home/sentry/.local/bin/mise activate bash)"' >> /home/sentry/.bashrc \
  && echo 'eval "$(/home/sentry/.local/bin/mise activate zsh)"' >> /home/sentry/.zshenv

# Pre-install Ruby at build time so the container starts immediately without
# downloading it at runtime. Switching Ruby versions requires a rebuild.
ARG RUBY_VERSION=latest

# Java is always installed (required for JRuby). It is listed in .mise.toml so
# it is available for all users regardless of which Ruby flavour they use.
RUN echo "📦 Pre-installing java@temurin-21..." && \
    /home/sentry/.local/bin/mise install "java@temurin-21" && \
    /home/sentry/.local/bin/mise use --global "java@temurin-21"

RUN echo "📦 Pre-installing ruby@${RUBY_VERSION} (precompiled)..." && \
    MISE_RUBY_COMPILE=0 /home/sentry/.local/bin/mise install "ruby@${RUBY_VERSION}" && \
    /home/sentry/.local/bin/mise use --global "ruby@${RUBY_VERSION}"

# Node.js is always needed for the svelte-mini e2e app.
RUN echo "📦 Pre-installing node@lts..." && \
  /home/sentry/.local/bin/mise install "node@lts" && \
  /home/sentry/.local/bin/mise use --global "node@lts"

# Install headless Chromium via Playwright (includes all system dependencies).
# Symlink the binary into ~/.local/bin which is already on PATH.
RUN /home/sentry/.local/share/mise/shims/npx playwright install chromium --with-deps
# Playwright lays out the binary under chrome-linux/ on arm64 and chrome-linux64/
# on x86_64 (since Playwright 1.57), so the glob has to match both.
RUN bash -c 'ln -sf /home/sentry/.cache/ms-playwright/chromium-*/chrome-linux*/chrome /home/sentry/.local/bin/chromium'
