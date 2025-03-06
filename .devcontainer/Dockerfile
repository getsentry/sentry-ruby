ARG IMAGE="bitnami/ruby"
ARG TAG="latest"

FROM ${IMAGE}:${TAG}

USER root
RUN apt-get update && apt-get install -y \
  gnupg \
  git \
  curl \
  wget \
  zsh \
  vim \
  build-essential \
  sudo \
  libssl-dev \
  libreadline-dev \
  zlib1g-dev \
  autoconf \
  bison \
  libyaml-dev \
  libncurses5-dev \
  libffi-dev \
  libgdbm-dev \
  && apt-get clean \
  && rm -rf /var/lib/apt/lists/*

RUN groupadd --gid 1000 sentry \
  && useradd --uid 1000 --gid sentry --shell /bin/zsh --create-home sentry

# Add sentry to sudoers with NOPASSWD option
RUN echo "sentry ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/sentry \
  && chmod 0440 /etc/sudoers.d/sentry

WORKDIR /workspace/sentry

RUN chown -R sentry:sentry /workspace/sentry
RUN mkdir /workspace/gems && chown -R sentry:sentry /workspace/gems

ARG TAG=latest

ENV LANG=C.UTF-8 \
  BUNDLE_JOBS=4 \
  BUNDLE_RETRY=3 \
  GEM_HOME=/workspace/gems/${TAG} \
  REDIS_HOST=redis

USER sentry

CMD ["ruby", "--version"]
