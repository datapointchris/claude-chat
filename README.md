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

## What the image contains

`node:22-bookworm-slim`, in two stages. The build stage clones the upstream tag, runs `npm ci` and
`npm run build`, then prunes to production dependencies. The runtime stage carries `dist/`,
`dist-server/`, `node_modules/` and `package.json`, plus `git`, `ripgrep`, `curl`, `tini` and a
pinned `claude`.

Debian rather than Alpine, for one blocking reason: CloudCLI's built-in terminal spawns `bash`
unconditionally on anything that is not Windows, and Alpine has no bash. Glibc also means the
native modules — `node-pty`, `better-sqlite3`, `bcrypt` — resolve prebuilt binaries instead of
compiling.

`package.json` is in the runtime stage because Node needs its `"type": "module"` to load the
compiled server as ESM, and because the server reads the version it reports on `/health` from it.

Both versions are build args, so a bump is one line:

```bash
docker build --build-arg CLOUDCLI_VERSION=v1.37.2 --build-arg CLAUDE_CODE_VERSION=2.1.241 .
```

## Running it

The container listens on 3001 and runs as uid 1000. Running as root breaks project creation:
`WORKSPACES_ROOT` falls back to the home directory, and `/root` is in CloudCLI's
`FORBIDDEN_WORKSPACE_PATHS`.

`docker-compose.yml` will not start without `CHAT_IMAGE_TAG` naming a `sha-<short>` tag. That is
deliberate — a floating tag makes a rollback ambiguous — so a bare `docker compose up` typed by
hand is expected to fail on the guard rather than silently pull something.

The clone directory doubles as the runtime directory. The compose file is git-pulled to `/srv/chat`
and its relative mounts resolve to `/srv/chat/data` and `/srv/chat/claude`, which sit inside the
working tree. `.gitignore` covers all three of those paths plus `.env`, so a future upstream file
at a colliding path cannot make `git pull` refuse on the host.

### Mounts

| Container path | Mode | What it is |
| --- | --- | --- |
| `/srv/corpus` | rw | `WORKSPACES_ROOT`. The agent may write here. |
| `/data` | rw | `HOME`. Holds `auth.db`, `.claude/projects`, `.cloudcli/`. |
| `/data/.claude/CLAUDE.md` | ro | Corpus guidance. |
| `/etc/claude-code/managed-settings.json` | ro | The tool deny list. |

`HOME=/data` is what puts state on the mount, and it has to be `HOME` rather than
`CLAUDE_CONFIG_DIR`. CloudCLI resolves `~/.claude` and `~/.cloudcli` through `os.homedir()` in
every provider and honours no override, so pointing `claude` elsewhere would leave CloudCLI reading
a directory nothing writes to. `HOME` is the only lever that moves both.

The deny list mounts at `/etc/claude-code/managed-settings.json` rather than
`~/.claude/settings.json` because user settings are the lowest of Claude Code's five precedence
levels. With the corpus writable, a `.claude/settings.local.json` written inside any corpus project
would override user settings; nothing overrides managed settings.

`/srv/chat/data/.claude/` has to exist and be owned by uid 1000 before the first start. The
`CLAUDE.md` bind nests inside the data mount, so Docker creates that directory as root if it is
missing and the container then cannot write `projects/` beside it.

### First start

With `IS_PLATFORM` on, `authenticateToken` reads the first user row and returns 500 when the users
table is empty, so a row has to exist even though nobody logs in. `POST /api/auth/register` creates
it and succeeds only while the table is empty. The deploy does this once, guarded on
`GET /api/auth/status` reporting `needsSetup`. The password is never used again.

## Configuration

`.env.example` declares the shape. Values are rendered by the deploy, never committed.
