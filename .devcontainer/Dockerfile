ARG IMAGE="ruby"
ARG VERSION="3.4.5"
ARG DISTRO="slim-bookworm"

# Base stage for sentry services
FROM ${IMAGE}:${VERSION}-${DISTRO} AS base

USER root
RUN apt-get update && apt-get install -y --no-install-recommends \
  sudo \
  gnupg \
  git \
  curl \
  wget \
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
  && apt-get clean \
  && rm -rf /var/lib/apt/lists/*

# Install Chromium for Selenium tests (works on both amd64 and arm64)
RUN apt-get update && apt-get install -y --no-install-recommends \
  chromium \
  chromium-driver \
  && apt-get clean \
  && rm -rf /var/lib/apt/lists/*

RUN groupadd --gid 1000 sentry \
  && useradd --uid 1000 --gid sentry --shell /bin/bash --create-home sentry

WORKDIR /workspace/sentry
RUN chown -R sentry:sentry /workspace/sentry
RUN mkdir /workspace/gems && chown -R sentry:sentry /workspace/gems

ARG VERSION
ARG GEM_HOME="/workspace/gems/${VERSION}"

ENV LANG=C.UTF-8 \
  BUNDLE_JOBS=4 \
  BUNDLE_RETRY=3 \
  GEM_HOME=/workspace/gems/${VERSION} \
  PATH=$PATH:${GEM_HOME}/bin \
  REDIS_HOST=redis

USER sentry

# Copy source code
COPY --chown=sentry:sentry . .

# Rails mini stage - extends base with specific entrypoint
FROM base AS rails-mini

USER root
# Copy and set up entrypoint script for rails mini
COPY --chown=root:root .devcontainer/entrypoint-rails-mini.sh /usr/local/bin/rails-entrypoint.sh
RUN chmod +x /usr/local/bin/rails-entrypoint.sh

USER sentry
ENTRYPOINT ["/usr/local/bin/rails-entrypoint.sh"]

# Svelte mini stage
FROM ${IMAGE}:${VERSION}-${DISTRO} AS svelte-mini

USER root
RUN apt-get update && apt-get install -y --no-install-recommends \
  sudo \
  git \
  curl \
  nodejs \
  npm \
  && apt-get clean \
  && rm -rf /var/lib/apt/lists/*

RUN groupadd --gid 1000 sentry \
  && useradd --uid 1000 --gid sentry --shell /bin/bash --create-home sentry

# Copy and set up entrypoint script for svelte mini
COPY --chown=root:root .devcontainer/entrypoint-svelte-mini.sh /usr/local/bin/svelte-entrypoint.sh
RUN chmod +x /usr/local/bin/svelte-entrypoint.sh

# Allow sentry user to use sudo without password for chown
RUN echo "sentry ALL=(ALL) NOPASSWD: /bin/chown" >> /etc/sudoers

WORKDIR /workspace/sentry
RUN chown -R sentry:sentry /workspace/sentry

USER sentry

# Copy source code
COPY --chown=sentry:sentry . .

ENTRYPOINT ["/usr/local/bin/svelte-entrypoint.sh"]
