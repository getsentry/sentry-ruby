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

WORKDIR /workspaces/sentry-ruby

RUN chown -R sentry:sentry /workspaces/sentry-ruby

ENV LANG=C.UTF-8 \
  BUNDLE_JOBS=4 \
  BUNDLE_RETRY=3 \
  REDIS_HOST=localhost \
  PATH=/home/sentry/.local/share/mise/shims:/home/sentry/.local/bin:$PATH

USER sentry

# Pre-create the bundle directory owned by sentry so that a Docker named volume
# mounted here is initialised with the correct ownership (Docker copies image
# directory content when a volume is first attached).
RUN mkdir -p /home/sentry/bundle

# Chromium, ChromeDriver, mise, and the toolchain (Java, Ruby, Node) are
# installed by the local `./features/tools` dev container feature, which runs
# after this Dockerfile — see devcontainer.json.
