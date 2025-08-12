ARG IMAGE="ruby"

FROM ${IMAGE} AS build

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
  nodejs \
  npm \
  chromium \
  chromium-driver \
  && apt-get clean \
  && rm -rf /var/lib/apt/lists/*

RUN echo "sentry ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/sentry \
  && chmod 0440 /etc/sudoers.d/sentry

RUN groupadd --gid 1000 sentry \
  && useradd --uid 1000 --gid sentry --shell /bin/bash --create-home sentry

WORKDIR /workspace/sentry

RUN chown -R sentry:sentry /workspace/sentry

ARG VERSION
ARG GEM_HOME="/workspace/sentry/vendor/gems/${VERSION}"

ENV LANG=C.UTF-8 \
  BUNDLE_JOBS=4 \
  BUNDLE_RETRY=3 \
  GEM_HOME=/workspace/sentry/vendor/gems/${VERSION} \
  PATH=$PATH:${GEM_HOME}/bin \
  REDIS_HOST=redis

USER sentry
