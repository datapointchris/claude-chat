# syntax=docker/dockerfile:1

# CloudCLI is compiled from source because VITE_IS_PLATFORM is baked into the
# client bundle at build time. The published npm tarball ships dist/ with the
# flag false, which renders a login form against a server that no longer
# checks one.
ARG NODE_IMAGE=node:22-bookworm-slim

FROM ${NODE_IMAGE} AS build

ARG CLOUDCLI_VERSION=v1.37.2

# git clones the source. The compilers are insurance for a CLOUDCLI_VERSION
# bump: on glibc, node-pty, better-sqlite3 and bcrypt all resolve prebuilt
# binaries and npm ci needs no toolchain, but a future version can add a
# dependency that has none. The layer is cached and never reaches runtime.
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
RUN git clone --depth 1 --branch "${CLOUDCLI_VERSION}" \
      https://github.com/siteboon/claudecodeui.git . \
 && npm ci --no-audit --no-fund

# Read by src/shared/utils.ts through import.meta.env, which Vite substitutes
# into dist/, and by server/shared/utils.ts through process.env at start.
ENV VITE_IS_PLATFORM=true
# Never add --omit=optional to the prune. Optional is where the Claude Agent
# SDK's platform binary lives: @anthropic-ai/claude-agent-sdk-linux-x64 is
# marked optional in the lockfile, and omitting it removes the SDK's
# executable.
RUN npm run build \
 && npm prune --omit=dev


FROM ${NODE_IMAGE} AS runtime

ARG CLAUDE_CODE_VERSION=2.1.241

RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      ca-certificates \
      curl \
      git \
      ripgrep \
      tini \
 && rm -rf /var/lib/apt/lists/* \
 && npm install -g --no-audit --no-fund \
      "@anthropic-ai/claude-code@${CLAUDE_CODE_VERSION}"

WORKDIR /app

# server/index.ts resolves the app root from dist-server/server/ and reads
# package.json there for the version in /health. Node also needs its
# "type": "module" to load the compiled output as ESM.
COPY --from=build /src/package.json ./package.json
COPY --from=build /src/dist ./dist
COPY --from=build /src/dist-server ./dist-server
COPY --from=build /src/node_modules ./node_modules

# Created owned by uid 1000 so the image also runs without the data mount.
RUN install -d -o node -g node /data

# CloudCLI resolves ~/.claude and ~/.cloudcli through os.homedir() and honours
# no override, so HOME is what puts transcripts and assets on the data mount.
ENV HOME=/data \
    NODE_ENV=production \
    SERVER_PORT=3001 \
    HOST=0.0.0.0

# WORKSPACES_ROOT falls back to the home directory, and /root is in
# FORBIDDEN_WORKSPACE_PATHS, so running as root breaks project creation.
USER 1000:1000

EXPOSE 3001

ENTRYPOINT ["/usr/bin/tini", "--"]
CMD ["node", "/app/dist-server/server/index.js"]
