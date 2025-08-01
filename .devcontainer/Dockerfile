ARG IMAGE="ruby"
ARG VERSION="3.4.5"
ARG DISTRO="slim-bookworm"

# Rails mini stage
FROM ${IMAGE}:${VERSION}-${DISTRO} AS rails-mini

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

# Install Ruby dependencies for rails mini
COPY --chown=sentry:sentry . .
RUN bundle install --gemfile=sentry-ruby/Gemfile
RUN bundle install --gemfile=sentry-rails/Gemfile

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

WORKDIR /workspace/sentry
RUN chown -R sentry:sentry /workspace/sentry

USER sentry

# Install npm dependencies for svelte mini
COPY --chown=sentry:sentry . .
RUN cd spec/apps/svelte-mini && npm install
