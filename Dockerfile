# syntax=docker/dockerfile:1

# CloudCLI is compiled from source because VITE_IS_PLATFORM is baked into the
# client bundle at build time, and the published npm tarball ships it false.
FROM node:24-trixie-slim AS build

RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      build-essential \
      ca-certificates \
      git \
      python3 \
 && rm -rf /var/lib/apt/lists/*

# electron is a devDependency of the desktop build and its binary is ~100MB.
ENV ELECTRON_SKIP_BINARY_DOWNLOAD=1

WORKDIR /src
RUN git clone --depth 1 https://github.com/siteboon/claudecodeui.git . \
 && npm ci --no-audit --no-fund

ENV VITE_IS_PLATFORM=true
# Never add --omit=optional: the Claude Agent SDK's platform binary is optional.
RUN npm run build \
 && npm prune --omit=dev


FROM node:24-trixie-slim AS runtime

RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      build-essential \
      ca-certificates \
      curl \
      eza \
      fd-find \
      file \
      git \
      jq \
      less \
      nano \
      procps \
      python3 \
      python3-dev \
      python3-pip \
      python3-venv \
      ripgrep \
      sqlite3 \
      sudo \
      tini \
      tokei \
      tree \
      unzip \
      vim-tiny \
      wget \
      xz-utils \
      zip \
 && rm -rf /var/lib/apt/lists/* \
 && rm -f /usr/lib/python3*/EXTERNALLY-MANAGED \
 && ln -s /usr/bin/fdfind /usr/local/bin/fd \
 && npm install -g --no-audit --no-fund @anthropic-ai/claude-code@latest

# Debian's yq is a different program from the Go one the fleet uses.
RUN curl -fsSL -o /usr/local/bin/yq \
      https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64 \
 && chmod 0755 /usr/local/bin/yq \
 && curl -LsSf https://astral.sh/uv/install.sh | UV_INSTALL_DIR=/usr/local/bin sh

# The agent runs as uid 1000 and installs what a task needs.
RUN echo 'node ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/node \
 && chmod 0440 /etc/sudoers.d/node

WORKDIR /app

# server/index.ts resolves the app root from dist-server/server/ and reads
# package.json there for the version in /health.
COPY --from=build /src/package.json ./package.json
COPY --from=build /src/dist ./dist
COPY sw.js ./dist/sw.js
COPY --from=build /src/dist-server ./dist-server
COPY --from=build /src/node_modules ./node_modules

# Created owned by uid 1000 so the image also runs without the data mount.
RUN install -d -o node -g node /data

# CloudCLI resolves ~/.claude and ~/.cloudcli through os.homedir(), so HOME is
# what puts transcripts, assets and user installs on the data mount.
ENV VITE_IS_PLATFORM=true \
    HOME=/data \
    NODE_ENV=production \
    SERVER_PORT=3001 \
    HOST=0.0.0.0 \
    PIP_BREAK_SYSTEM_PACKAGES=1 \
    PATH=/data/.local/bin:${PATH}

# WORKSPACES_ROOT falls back to the home directory, and /root is in
# FORBIDDEN_WORKSPACE_PATHS, so running as root breaks project creation.
USER 1000:1000

EXPOSE 3001

ENTRYPOINT ["/usr/bin/tini", "--"]
CMD ["node", "/app/dist-server/server/index.js"]
