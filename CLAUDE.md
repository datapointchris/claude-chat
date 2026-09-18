# claude-chat

This repo builds one container image and stops. CloudCLI is third-party and none of its source is
vendored here. The Dockerfile clones upstream, compiles it, and installs `claude` and the agent's
toolchain beside it. Nothing here is patched, so this is packaging rather than a fork.

Anything that is not the image — the host, its corpus, the agent's guidance and permissions, the
reverse-proxy route, the backups — is provisioned elsewhere and does not belong in this repo.

## What this dependency reaches, and what that costs

CloudCLI is a third-party web application that runs a coding agent, and what it holds is unusual
for something installed as an npm package.

**What it can reach.** Everything under `WORKSPACES_ROOT`, read and write, including a shell spawned
through `node-pty` and the agent's tool calls. `$HOME` on a persistent mount, holding the
transcripts, the MCP configuration and the session database. A live `CLAUDE_CODE_OAUTH_TOKEN`, a
bearer credential for a paid API usable from anywhere. Unrestricted outbound network.

**What it gives that nothing safer does.** A browser front end for Claude Code from a phone, against
a corpus that stays on the host. A terminal does not reach a phone, and a hosted service moves the corpus.

**Blast radius if it egresses once**, worst first: the token, whose only remedy is rotation; the
corpus in full; the transcripts, which carry everything ever asked about it. The database holds one
password hash for an account nobody logs into.

**What is done about it.** The tool deny list is mounted read-only at the managed-settings path,
which no lower-precedence file can override. The container runs as uid 1000 with
`no-new-privileges`. The reverse proxy enforces authentication, and the application's own login is
compiled out rather than bypassed. Outbound network is accepted rather than mitigated.

## Two things that will bite

**`VITE_IS_PLATFORM` has to be true in both halves.** The client's is compiled into `dist/` and the
server's is read from the environment. The image sets the server's so they cannot drift, and the
build sets the client's. A build that omits it ships a login form; an environment that omits it
rejects every API call. Neither failure shows up on `/health`.

**The clone directory doubles as the runtime directory on the host.** `claude/` and `.env` live
inside the working tree and are gitignored, as is `data/`, which nothing uses at runtime. An
upstream file landing at any of those paths would make `git pull` fail on the host with nothing
wrong in the repo.

The database and transcripts stay out of it, at `/var/db/chat`. The deploy runs `git` in the clone
directory, so anything ignored there is one `git clean -fdx` away from being deleted.
