# claude-chat

The container image behind `chat.ichrisbirch.com`.

It packages [CloudCLI](https://github.com/siteboon/claudecodeui), a web front end for Claude Code,
and a pinned `claude` binary for it to drive. It holds no application source — CloudCLI is
third-party and this repo only builds it.

## Why an image rather than an npm install

CloudCLI publishes no container image. Its own Dockerfile targets Docker Sandboxes microVMs and
needs the `sbx` CLI.

It also has to be compiled rather than installed. Authentication at `chat.ichrisbirch.com` is
Authelia ForwardAuth at the edge, so CloudCLI's own login is switched off with `IS_PLATFORM`. That
flag exists twice — the server reads `process.env.VITE_IS_PLATFORM` at startup, and the client reads
`import.meta.env.VITE_IS_PLATFORM`, which Vite bakes into `dist/` at build time. The published npm
tarball ships `dist/` built with it false, so setting the variable alone gives a login form talking
to a server that no longer checks one.

## Where the rest lives

The LXC, its corpus, the agent's `CLAUDE.md` and tool settings, the Traefik route and the backups
are all in the homelab repo under `containers/chat-lxc/`. This repo ends at the image.
