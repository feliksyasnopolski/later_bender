FROM ubuntu:24.04

ARG DEBIAN_FRONTEND=noninteractive

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
      nodejs npm sqlite3 postgresql-client redis-tools \
      shellcheck shfmt \
      libxml2-utils xmlstarlet \
      man-db manpages groff pandoc imagemagick ffmpeg poppler-utils ghostscript \
    && locale-gen en_US.UTF-8 \
    && git lfs install --system \
    && ln -s /usr/bin/fdfind /usr/local/bin/fd \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

COPY workspace-image-smoke.sh /usr/local/bin/workspace-image-smoke
RUN /usr/local/bin/workspace-image-smoke

WORKDIR /workspace
CMD ["sleep", "infinity"]
