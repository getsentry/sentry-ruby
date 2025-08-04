ARG IMAGE="ruby"
ARG VERSION="3.4.5"
ARG DISTRO="slim-bookworm"

FROM ${IMAGE}:${VERSION}-${DISTRO} AS build

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
ARG GEM_HOME="/workspace/gems/${VERSION}"

RUN mkdir /workspace/gems && chown -R sentry:sentry /workspace/gems

ENV LANG=C.UTF-8 \
  BUNDLE_JOBS=4 \
  BUNDLE_RETRY=3 \
  GEM_HOME=/workspace/gems/${VERSION} \
  PATH=$PATH:${GEM_HOME}/bin \
  REDIS_HOST=redis

FROM build AS dev

USER sentry

COPY .devcontainer/entrypoint.sh /workspace/entrypoint.sh

ENTRYPOINT ["/workspace/entrypoint.sh"]

FROM build AS test

COPY . .

RUN chown -R sentry:sentry .

USER sentry

RUN gem install foreman && \
  bundle install && \
  cd spec/apps/rails-mini && \
  bundle install

RUN cd spec/apps/svelte-mini && \
  npm install
