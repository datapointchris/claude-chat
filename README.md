# claude-chat

The container image behind a private web front end for Claude Code. A phone or any browser drives
the agent against a corpus on one host, and the corpus never leaves that host.

It builds [CloudCLI](https://github.com/siteboon/claudecodeui), a third-party web front end for
Claude Code, and puts the `claude` binary and a working toolchain beside it. No CloudCLI source
lives here. The Dockerfile clones upstream and compiles it, so this is packaging rather than a fork.

The repo ends at the image and the compose file that runs it. The host, its corpus, the agent's
guidance and deny list, the authenticating reverse proxy and the backups are provisioned elsewhere.

## Install

```bash
docker pull ghcr.io/datapointchris/claude-chat:latest   # what main last published, after its smoke test
docker build -t claude-chat .                           # or build it from a clone
```

The image is amd64 only. Its Dockerfile downloads the amd64 build of `yq`.

## Starting from scratch

On a host with Docker and Compose:

```bash
git clone https://github.com/datapointchris/claude-chat.git   # the compose file and the .env shape
cd claude-chat                          # compose runs from this clone, so it stays on the host
cp .env.example .env                    # gitignored, and kept out of the build context
claude setup-token                      # on any machine with claude: the token .env needs
mkdir claude                            # gitignored; holds the one file compose mounts from here
$EDITOR claude/managed-settings.json    # the tool deny list; compose refuses to start without it
sudo install -d -o 1000 -g 1000 /srv/corpus /var/db/chat /var/db/chat/.claude   # the container's uid
sudo install -d /srv/claude-profile/{output-styles,skills,agents,commands}       # read-only, may be empty
docker compose up -d                    # pulls :latest and publishes host port 80
curl -fsS http://localhost/api/auth/status       # "needsSetup":true until a user row exists
curl -fsS http://localhost/api/auth/register -H 'Content-Type: application/json' \
  -d '{"username":"owner","password":"change-me"}'   # once; refused when a row exists
curl -fsS http://localhost/api/projects          # a JSON list: platform mode found its user
```

`.env` needs one value filled in, `CLAUDE_CODE_OAUTH_TOKEN`. `claude setup-token` needs a Claude
subscription. Every other key in `.env.example` carries a comment saying what it does, and works as
written. A blank `JWT_SECRET` is generated once and kept in the database.

Every bind in the compose file sets `create_host_path: false`. A missing source refuses to start
rather than being invented. Without that guard, Compose creates a missing source as a root-owned
directory. For `managed-settings.json` that would be a healthy-looking container running with no
deny list at all. The deny list is Claude Code settings JSON, with its rules under
`permissions.deny`.

`/var/db/chat/.claude` is created by hand because the profile binds nest inside the read-write data
mount. Docker creates a missing parent of a mount point as root. The container then cannot write
`projects/` beside it.

Platform mode needs one user row even though nobody logs in. Every authenticated route reads the
first user, and returns 500 while the table is empty. `register` succeeds only while the table is
empty. It wants a username of at least three characters and a password of at least six. The password
is never used again.

The app has no login of its own. Whatever reaches port 80 gets the agent and a shell. An
authenticating reverse proxy goes in front before that port is reachable from anywhere but the host.

## `Dockerfile` — CloudCLI compiled from source, because its login is decided at build time

```bash
docker build -t claude-chat .                                 # clones and compiles upstream's default branch
docker build --build-arg APP_NAME=Notebook -t claude-chat .   # what the browser tab says instead of Console
```

CloudCLI's own published images are Docker Sandbox templates. They run in a microVM through the
`sbx` CLI, not as a plain container under Compose. Its npm package cannot be installed instead,
because of one flag.

CloudCLI's login is switched off by `VITE_IS_PLATFORM`, and that flag exists twice. The server reads
`process.env.VITE_IS_PLATFORM` at startup. The client reads `import.meta.env.VITE_IS_PLATFORM`, which
Vite bakes into `dist/` at build time. The published npm tarball ships `dist/` built with it false.

**`VITE_IS_PLATFORM` has to be true in both halves.** The build sets the client's. The runtime stage
sets the server's, so the two cannot drift. A build that omits it ships a login form talking to a
server that never checks it. An environment that omits it renders the app against a server that
rejects every API call. Neither failure shows up on `/health`.

Both stages are Debian slim Node images. Debian rather than Alpine, for one blocking reason:
CloudCLI's terminal spawns `bash` on anything that is not Windows, and Alpine has no bash. The Node
major comes from the base image tag, not from upstream's `.nvmrc`. Upstream's README treats that
version as a minimum.

The build stage clones upstream, runs `npm ci` and `npm run build`, then prunes to production
dependencies. The runtime stage carries `dist/`, `dist-server/`, `node_modules/` and `package.json`.
`package.json` is there because Node needs its `"type": "module"` to load the compiled server as
ESM. The server also reads the version `/health` reports from it.

Beside the app, the agent gets `claude`, Python with pip, venv and `uv`, a C toolchain, and
passwordless `sudo`. It also gets `rg`, `fd`, `eza`, `jq`, `yq`, `tokei`, `sqlite3`, `tree` and
`less`. The `yq` is the Go one, downloaded, because Debian's `yq` is a different program. The smoke
test in `docker-publish.yml` fails the build when any binary it lists is missing. pip writes to the
system interpreter. User installs land in `/data/.local/bin`, which is on `PATH` and on the data
mount.

Nothing is pinned beyond the Node major. CloudCLI builds from the head of its default branch, not
from a release. `claude`, `yq` and `uv` come from their latest releases.

`rebrand.sh` runs over the built client. It sets the page title, the mobile app title and the
manifest's names to `APP_NAME`, which defaults to `Console`. It swaps the tab icon for a neutral mark
and drops the icons that carry upstream's artwork. It rewrites built output rather than upstream
source, which keeps this packaging.

`sw.js` replaces CloudCLI's service worker. Upstream's worker caches under one fixed name in every
build, so a replacement image never invalidates the client a browser already holds. The app then
runs a stale client against a current server until someone clears site data by hand. The
replacement drops every cache, unregisters itself and reloads open tabs.

## `docker-compose.yml` — state on the data mount, the deny list where nothing outranks it

```bash
docker compose up -d          # pull_policy: always, so every start takes the newest :latest
docker compose ps             # healthy once /health has answered
docker compose logs -f chat   # CloudCLI's server log
```

The container listens on 3001, and compose publishes it on host port 80.

| Container path | Host source | Mode | What it is |
| --- | --- | --- | --- |
| `/srv/corpus` | `/srv/corpus` | rw | `WORKSPACES_ROOT`. The agent may write here. |
| `/data` | `/var/db/chat` | rw | `HOME`. Holds `auth.db`, `.claude/projects`, `.cloudcli/` and the agent's `CLAUDE.md`. |
| `/data/.claude/output-styles`, `skills`, `agents`, `commands` | `/srv/claude-profile/` | ro | The behavior profile, one directory per bind. |
| `/etc/claude-code/managed-settings.json` | `./claude/managed-settings.json` | ro | The tool deny list. |

The agent's `CLAUDE.md` has no bind of its own. It lives inside the data mount, so the agent can edit
its own instructions and the edit persists. The profile is mounted a directory at a time because
`/data/.claude` is live: the CLI writes `settings.json`, `projects/` and `sessions/` there.

`HOME=/data` is what puts state on the mount. It has to be `HOME` rather than `CLAUDE_CONFIG_DIR`.
CloudCLI reads transcripts, skills and credentials from `~/.claude` through `os.homedir()` alone, and
`~/.cloudcli` has no override at all. Pointing `claude` elsewhere would leave CloudCLI scanning a
transcript directory nothing writes to. `HOME` is the one lever that moves both.

The deny list mounts at the managed-settings path rather than `~/.claude/settings.json`. User
settings are the lowest precedence Claude Code reads. With the corpus writable, a
`.claude/settings.local.json` written inside any corpus project would override them. Nothing
overrides managed settings.

The container runs as uid 1000, the Node image's `node` user. That user has passwordless `sudo`, so
the agent installs what a task needs. Compose leaves out `no-new-privileges`, because it blocks the
setuid bit `sudo` needs.

## What it reaches — the corpus, a shell, a paid token and the open network

The container reads and writes everything under `WORKSPACES_ROOT`. Its terminal spawns a shell
through `node-pty`. `$HOME` holds the transcripts, the MCP configuration and the session database.
The environment holds `CLAUDE_CODE_OAUTH_TOKEN`, a bearer credential for a paid API, usable from
anywhere. Outbound network is unrestricted.

If it egresses once, the token goes first, and rotation is its only remedy. The corpus goes in full.
The transcripts carry everything ever asked about it. The database holds one password hash, for an
account nobody logs into.

The defenses are the deny list at the managed-settings path, the authenticating proxy, and a login
compiled out rather than bypassed. Outbound network is accepted rather than mitigated.

## The clone doubles as the runtime directory, so the database lives outside it

Compose reads `.env` and `claude/managed-settings.json` from the clone it runs in. Both sit inside
the working tree. `.gitignore` covers them and `data/`, so no committed file can land on one of
those paths and make `git pull` refuse on the host.

The database and transcripts stay out of the clone, at `/var/db/chat`. A deploy that pulls into a
git checkout invites `git clean -fdx` to unstick a pull, and `-x` reaches ignored files. `data/` is
ignored for that collision alone, and nothing uses it at runtime.

`.dockerignore` excludes the same paths and `.git/`. A build run from the clone never sends `.env`,
and the token in it, to the Docker daemon.

## `docker-publish.yml` — the image pushed is the image that was tested

Every push and pull request builds the image, starts it as the user the image declares, and asserts
against it:

- `/health` answers `ok`.
- The process runs as uid 1000.
- The agent's toolchain is on `PATH`, and `sudo` and pip work.
- Nothing a viewer reads in the page or the manifest names the product.
- The image declares `VITE_IS_PLATFORM`, and platform mode is live on the server.
- No client chunk carries the login form.

Only a push to `main` publishes. It tags and pushes the local image those checks ran against, as
`:latest`. A second build would rebuild and could publish untested bytes.
