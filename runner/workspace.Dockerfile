FROM ubuntu:24.04

ARG DEBIAN_FRONTEND=noninteractive
ARG NODE_VERSION=22.23.2
ARG NODE_SHA256=fff4078c5def658577f92c88db7db3bc0072924bfb93fe52c1e744a54e94abb8

ENV LANG=C.UTF-8 \
    LANGUAGE=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    TZ=UTC

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

RUN apt-get update \
    && apt-get install --yes --no-install-recommends \
      bash bash-completion ca-certificates locales tzdata \
      coreutils findutils diffutils grep sed gawk patch gettext parallel bc time \
      curl wget git git-lfs openssh-client rsync jq yq ripgrep fd-find fzf tree less vim nano tmux \
      file xxd bsdextrautils binutils strace lsof procps psmisc iproute2 iputils-ping dnsutils \
      netcat-openbsd socat traceroute openssl gnupg \
      unzip zip p7zip-full tar gzip bzip2 xz-utils zstd \
      build-essential pkg-config cmake ninja-build make autoconf automake libtool clang llvm lld gdb \
      python3 python3-pip python3-venv pipx ruby ruby-dev ruby-bundler \
      sqlite3 postgresql-client redis-tools \
      shellcheck shfmt \
      libxml2-utils xmlstarlet \
      man-db manpages groff pandoc imagemagick ffmpeg poppler-utils ghostscript \
    && locale-gen en_US.UTF-8 \
    && git lfs install --system \
    && mkdir -p /opt/nodejs \
    && node_archive="node-v${NODE_VERSION}-linux-arm64.tar.xz" \
    && curl --fail --silent --show-error --location "https://nodejs.org/dist/v${NODE_VERSION}/${node_archive}" --output "/tmp/${node_archive}" \
    && echo "${NODE_SHA256}  /tmp/${node_archive}" | sha256sum --check --status \
    && tar --extract --file "/tmp/${node_archive}" --xz --strip-components=1 --directory /opt/nodejs \
    && ln -s /opt/nodejs/bin/node /usr/local/bin/node \
    && ln -s /opt/nodejs/bin/npm /usr/local/bin/npm \
    && ln -s /opt/nodejs/bin/npx /usr/local/bin/npx \
    && ln -s /opt/nodejs/bin/corepack /usr/local/bin/corepack \
    && rm -f "/tmp/${node_archive}" \
    && ln -s /usr/bin/fdfind /usr/local/bin/fd \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

COPY workspace-image-smoke.sh /usr/local/bin/workspace-image-smoke
RUN /usr/local/bin/workspace-image-smoke

WORKDIR /workspace
CMD ["sleep", "infinity"]
