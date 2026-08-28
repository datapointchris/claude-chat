# claude-chat

This repo builds one container image and stops. CloudCLI is third-party and none of its source is
vendored here. The Dockerfile clones upstream, compiles it, and installs `claude` and the agent's
toolchain beside it. Nothing here is patched, so this is packaging rather than a fork.

Anything that is not the image — the host, its corpus, the agent's guidance and permissions, the
reverse-proxy route, the backups — is provisioned elsewhere and does not belong in this repo.

## What this dependency reaches, and what that costs

CloudCLI is a third-party web application that runs a coding agent. It is worth recording what it
holds, because the answer is unusual for something installed as an npm package.

**What it can reach.** Everything under `WORKSPACES_ROOT`, read and write, including a shell it
spawns through `node-pty` and the agent's own tool calls. `$HOME` on a persistent mount, which is
where the agent's transcripts, its MCP configuration and the session database live. A live
`CLAUDE_CODE_OAUTH_TOKEN` in its environment, which is a credential for a paid API that can be used
from anywhere. Outbound network, unrestricted.

**What it gives that nothing safer does.** A browser-reachable front end for Claude Code, from a
phone or a tablet, against a corpus that stays on the host. The alternatives are a terminal on the
machine, which does not reach a phone, or a hosted service, which would mean the corpus leaving.

**Blast radius if it egresses once.** The token is the worst of it: it is a bearer credential and
rotating it is the only remedy. Then the corpus, in full. Then the transcripts, which carry more
than the corpus does because they include everything ever asked about it. The database holds one
password hash for an account nobody logs into, so it is the least of the three.

**What is done about it.** The tool deny list is mounted at the managed-settings path, which no
lower-precedence file can override, and read-only so the agent cannot edit it. The container runs
as uid 1000 with `no-new-privileges`. Authentication is enforced at the reverse proxy, and the
application's own login is compiled out rather than merely bypassed. None of that constrains
outbound network, which remains accepted rather than mitigated.

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
