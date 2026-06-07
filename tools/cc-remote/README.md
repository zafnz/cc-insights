# cc-remote

Run **Claude Code in Remote Control mode** inside a Docker container for any
folder, so you can drive it from the Claude **desktop / mobile / web** app while
the code and tools run in an isolated, firewalled container on your machine.

```bash
tools/cc-remote/cc-remote.py /path/to/your/project
```

This scaffolds a self-contained `.devcontainer/` into the target folder, builds
the image, starts the container, and follows the logs — where a **session URL +
QR code** appear. Open it in the Claude app (or find the session by name at
claude.ai/code) and start chatting.

## How it works

`claude remote-control` (Claude Code ≥ 2.1.51) registers with `api.anthropic.com`
and **polls outbound over HTTPS** — Anthropic relays your app's messages to the
container. No inbound ports are opened for the control channel; the code/tools
run inside the container against the mounted folder.

```
Claude app (phone/desktop/web)  ──►  api.anthropic.com  ──►  container: `claude remote-control`
                                                               └─ /workspace = your folder (bind mount)
                                                               └─ ~/.claude   = shared docker volume
                                                               └─ egress firewall (Anthropic-only)
```

## Commands

| Command | Action |
|---|---|
| `cc-remote.py <folder>` / `up` | scaffold (if needed), build, start, follow logs |
| `cc-remote.py <folder> login`  | interactive shell to run `/login` (first-time auth) |
| `cc-remote.py <folder> logs`   | follow logs (URL / QR show here) |
| `cc-remote.py <folder> shell`  | bash shell in the running container |
| `cc-remote.py <folder> down`   | stop & remove the container |
| `cc-remote.py <folder> rebuild`| rebuild image (`--no-cache`) and restart |
| `cc-remote.py <folder> init`   | only scaffold `.devcontainer/`, don't start |

## Design decisions

* **Claude home:** the container has its **own** `~/.claude` stored in a *shared*
  docker volume (`cc-remote-claude-home`). Log in once; every project reuses it.
  The host's real `~/.claude` is never touched.
* **Auth:** generate a token on the host with `claude setup-token` and put it in
  `<folder>/.devcontainer/.env` as `CLAUDE_CODE_OAUTH_TOKEN` (or export it before
  running — the wrapper picks it up). Or use the `login` command. The login
  persists in the shared volume across restarts.
* **Firewall:** an iptables/ipset egress allowlist (needs `NET_ADMIN`/`NET_RAW`,
  already wired up). Default = Anthropic only. Widen via `allowed-domains.txt`,
  `EXTRA_ALLOWED_DOMAINS=` in `.env`, or `ALLOW_ALL=true` for full internet.
  Only **outbound** is restricted, so published ports always work.
* **Ports:** set `PORTS=3000,8080` in `.env` (1:1 host↔container) or add a
  `ports:` block to `docker-compose.yml`.
* **Self-contained:** everything lives in `<folder>/.devcontainer/`, so anyone
  can `cd .devcontainer && docker compose up --build` without this wrapper, and
  VS Code "Dev Containers" can open the folder directly.

## Editing & git from the host

The folder is bind-mounted, so **edit files and run `git` directly on the host**
— it's literally the same working tree and `.git`. Core git is path-independent,
so it doesn't matter that the container sees it at `/workspace`. The container
runs as your host uid/gid (set automatically) to avoid "dubious ownership".

Caveats:
* Don't run *mutating* git commands on the host and in the container at the exact
  same time (index.lock races).
* `git worktree` stores absolute paths, so the wrapper uses
  `claude remote-control --spawn same-dir` (no auto-worktrees) by default.
* On macOS, large repos are faster with VirtioFS enabled in Docker Desktop.

## Requirements

* Docker + Docker Compose v2
* A claude.ai subscription login (Remote Control needs a full-scope token, not a
  plain `ANTHROPIC_API_KEY`)
* Python 3 (stdlib only — no pip installs)
