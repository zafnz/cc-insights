#!/usr/bin/env python3
"""
cc-remote — run Claude Code in "Remote Control" mode inside a Docker container.

Spins up a container for a target folder so you can drive Claude from the
Claude desktop / mobile / web app (claude.ai/code). The container:

  * bind-mounts the target folder at /workspace (edit + run git from the host too)
  * persists the Claude home in a SHARED docker volume (log in once, reuse everywhere)
  * runs an egress firewall that by default only allows Anthropic's servers
  * makes it trivial to widen the firewall or publish app ports

The container setup files are scaffolded into <folder>/.devcontainer/ so the
project is self-contained: anyone can `cd .devcontainer && docker compose up`
without this wrapper, and VS Code "Dev Containers" can open it directly.

Usage:
    cc-remote.py <folder> [up]      # scaffold (if needed), build, start, follow logs
    cc-remote.py <folder> down      # stop and remove the container
    cc-remote.py <folder> logs      # follow the container logs (URL / QR appear here)
    cc-remote.py <folder> login     # interactive shell to run /login (first-time auth)
    cc-remote.py <folder> shell     # open a shell in the running container
    cc-remote.py <folder> rebuild   # rebuild the image and restart
    cc-remote.py <folder> init      # only scaffold .devcontainer/, do not start

Authentication (recommended): on the HOST run `claude setup-token`, then either
export CLAUDE_CODE_OAUTH_TOKEN before running this, or paste it into
<folder>/.devcontainer/.env. Alternatively use `cc-remote.py <folder> login`.
"""

import argparse
import os
import re
import shutil
import subprocess
import sys
from pathlib import Path

# --------------------------------------------------------------------------- #
# Scaffolded files. Kept here so this stays a single, dependency-free script.
# NB: these are plain strings (not f-strings) so ${...} / $VAR survive intact.
# --------------------------------------------------------------------------- #

DOCKERFILE = r"""# Claude Code remote-control container.
# Claude Code is baked in so the firewall doesn't need npm egress at runtime.
FROM node:22-bookworm-slim

ARG USER_UID=1000
ARG USER_GID=1000

# Tools: git for VCS, iptables/ipset/dnsutils for the egress firewall,
# gosu to drop privileges after the firewall is applied, plus the usual basics.
RUN apt-get update && apt-get install -y --no-install-recommends \
        git ca-certificates curl iptables ipset dnsutils gosu sudo procps less \
    && rm -rf /var/lib/apt/lists/*

RUN npm install -g @anthropic-ai/claude-code

# A non-root user whose uid/gid match the host, so bind-mounted files and git
# operations don't trip over ownership ("dubious ownership") between host/container.
RUN if getent group ${USER_GID} >/dev/null; then \
        groupmod -n claude "$(getent group ${USER_GID} | cut -d: -f1)"; \
    else groupadd -g ${USER_GID} claude; fi \
    && if getent passwd ${USER_UID} >/dev/null; then \
        usermod -l claude -d /home/claude -m "$(getent passwd ${USER_UID} | cut -d: -f1)"; \
    else useradd -u ${USER_UID} -g ${USER_GID} -m -s /bin/bash claude; fi \
    && mkdir -p /home/claude/.claude /workspace \
    && chown -R ${USER_UID}:${USER_GID} /home/claude

COPY init-firewall.sh /usr/local/bin/init-firewall.sh
COPY entrypoint.sh    /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/init-firewall.sh /usr/local/bin/entrypoint.sh

WORKDIR /workspace
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
# Default: start the remote-control server. PROJECT_NAME comes from .env.
CMD ["sh", "-c", "exec claude remote-control --name \"${PROJECT_NAME:-cc-remote}\" --spawn same-dir"]
"""

ENTRYPOINT = r"""#!/usr/bin/env bash
# Runs as root: apply the firewall, fix ownership, then drop to the 'claude' user.
set -euo pipefail

if [ "${ALLOW_ALL:-false}" = "true" ]; then
    echo "[cc-remote] ALLOW_ALL=true — firewall disabled, full internet access."
else
    /usr/local/bin/init-firewall.sh || {
        echo "[cc-remote] WARNING: firewall setup failed. Is the container started"
        echo "[cc-remote]          with --cap-add=NET_ADMIN --cap-add=NET_RAW?"
    }
fi

# Make sure the persistent Claude home is writable by our user.
mkdir -p /home/claude/.claude
chown claude:claude /home/claude 2>/dev/null || true
chown -R claude:claude /home/claude/.claude 2>/dev/null || true

# Git is happy operating on the bind mount regardless of where the host mounts it.
git config --system --add safe.directory /workspace 2>/dev/null || true
git config --system --add safe.directory '*' 2>/dev/null || true

cd /workspace
exec gosu claude "$@"
"""

INIT_FIREWALL = r"""#!/usr/bin/env bash
# Minimal egress allowlist firewall.
#
# Only OUTBOUND traffic is restricted. INBOUND is left untouched so published
# ports (docker -p / compose ports:) keep working with zero extra config.
#
# Allowed by default: DNS, anything already ESTABLISHED, and HTTPS/HTTP to the
# hosts resolved from allowed-domains.txt + $EXTRA_ALLOWED_DOMAINS.
#
# To widen access: add lines to allowed-domains.txt, set EXTRA_ALLOWED_DOMAINS
# in .env, or set ALLOW_ALL=true to skip this entirely.
set -euo pipefail

DOMAINS_FILE="${ALLOWED_DOMAINS_FILE:-/etc/cc-remote/allowed-domains.txt}"

echo "[firewall] applying egress allowlist..."

# Reset OUTPUT only.
iptables -F OUTPUT
iptables -P OUTPUT DROP
iptables -P INPUT ACCEPT
iptables -P FORWARD ACCEPT

# Loopback + return traffic for connections we (or published ports) initiated.
iptables -A OUTPUT -o lo -j ACCEPT
iptables -A OUTPUT -m state --state ESTABLISHED,RELATED -j ACCEPT

# DNS — needed to resolve the allowlist below and at runtime.
iptables -A OUTPUT -p udp --dport 53 -j ACCEPT
iptables -A OUTPUT -p tcp --dport 53 -j ACCEPT

# Build the allowed-IP set from the domain list.
ipset destroy cc_allowed 2>/dev/null || true
ipset create cc_allowed hash:ip family inet

add_domain() {
    local d="$1"
    [ -z "$d" ] && return 0
    case "$d" in \#*) return 0 ;; esac
    local ip
    for ip in $(getent ahostsv4 "$d" 2>/dev/null | awk '{print $1}' | sort -u); do
        ipset add cc_allowed "$ip" 2>/dev/null || true
    done
    echo "[firewall]   allow $d"
}

if [ -f "$DOMAINS_FILE" ]; then
    while IFS= read -r line; do add_domain "$(echo "$line" | tr -d '[:space:]')"; done < "$DOMAINS_FILE"
fi
# Comma- or space-separated extras from the environment.
if [ -n "${EXTRA_ALLOWED_DOMAINS:-}" ]; then
    for d in $(echo "$EXTRA_ALLOWED_DOMAINS" | tr ',' ' '); do add_domain "$d"; done
fi

# Permit HTTPS/HTTP to the resolved set.
iptables -A OUTPUT -p tcp -m set --match-set cc_allowed dst --dport 443 -j ACCEPT
iptables -A OUTPUT -p tcp -m set --match-set cc_allowed dst --dport 80  -j ACCEPT

echo "[firewall] done. ($(ipset list cc_allowed | grep -c '^[0-9]') IPs allowed)"
echo "[firewall] NOTE: IPs are a snapshot from container start. If Anthropic"
echo "[firewall]       rotates CDN IPs you may need 'rebuild', or set ALLOW_ALL=true."
"""

ALLOWED_DOMAINS = """# Egress allowlist for cc-remote — one domain per line. Lines starting with # are ignored.
# These are the minimum needed for Claude Code Remote Control to authenticate
# and run. Add your own below (or use EXTRA_ALLOWED_DOMAINS in .env).

api.anthropic.com
claude.ai
platform.claude.com
console.anthropic.com

# --- common extras you may want to uncomment ---
# registry.npmjs.org
# github.com
# raw.githubusercontent.com
# objects.githubusercontent.com
# pypi.org
# files.pythonhosted.org
"""

# {token} is substituted by the wrapper; everything else is literal.
ENV_EXAMPLE = """# cc-remote configuration. Copy to .env (this file is the template).
# .env is git-ignored — safe place for your token.

# Full-scope OAuth token from `claude setup-token` on the HOST.
# Leave blank to instead authenticate interactively with `cc-remote <folder> login`.
CLAUDE_CODE_OAUTH_TOKEN={token}

# Display name shown in claude.ai/code and the mobile app.
PROJECT_NAME={project_name}

# Host uid/gid — keeps bind-mounted file ownership / git sane. Set by the wrapper.
USER_UID={uid}
USER_GID={gid}

# Firewall: set to true to disable the egress allowlist (full internet).
ALLOW_ALL=false

# Extra egress domains, comma-separated, e.g. github.com,pypi.org
EXTRA_ALLOWED_DOMAINS=

# App ports to publish to the host, comma-separated, e.g. 3000,8080
# (each maps host:container 1:1). Used by the wrapper to build the override file.
PORTS=

# Reduce non-essential outbound traffic / disable the auto-updater.
CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1
DISABLE_AUTOUPDATER=1
"""

DOCKER_COMPOSE = r"""# cc-remote — Claude Code Remote Control container.
# Standalone use (no wrapper):  cp .env.example .env  &&  docker compose up --build
services:
  claude:
    build:
      context: .
      args:
        USER_UID: ${USER_UID:-1000}
        USER_GID: ${USER_GID:-1000}
    image: cc-remote:${PROJECT_NAME:-app}
    container_name: cc-remote-${PROJECT_NAME:-app}
    env_file: .env
    # Required for the egress firewall (iptables/ipset).
    cap_add:
      - NET_ADMIN
      - NET_RAW
    volumes:
      # The project folder (parent of .devcontainer) -> /workspace.
      - ..:/workspace:cached
      # SHARED, persistent Claude home: log in once, reused by every project.
      - claude-home:/home/claude/.claude
      - ./allowed-domains.txt:/etc/cc-remote/allowed-domains.txt:ro
    working_dir: /workspace
    stdin_open: true
    tty: true
    restart: unless-stopped
    # To publish app ports without the wrapper, add e.g.:
    # ports:
    #   - "3000:3000"

volumes:
  claude-home:
    # Fixed name => shared across all cc-remote projects on this host.
    name: cc-remote-claude-home
"""

DEVCONTAINER_JSON = r"""{
  "name": "cc-remote",
  "dockerComposeFile": ["docker-compose.yml"],
  "service": "claude",
  "workspaceFolder": "/workspace",
  "remoteUser": "claude",
  "overrideCommand": true,
  "shutdownAction": "stopCompose"
}
"""

GITIGNORE = """# cc-remote host-specific / secret files
.env
docker-compose.override.yml
"""

README = """# cc-remote (.devcontainer)

Runs Claude Code in **Remote Control** mode in a container so you can drive it
from the Claude desktop / mobile / web app, while the code lives on your machine.

## Quick start (with the wrapper)

    cc-remote.py /path/to/this/folder

Then watch the logs for a session URL + QR code and open it in the Claude app
(or find the session by name at claude.ai/code).

## Quick start (standalone, no wrapper)

    cd .devcontainer
    cp .env.example .env        # add CLAUDE_CODE_OAUTH_TOKEN, or use `login` below
    docker compose up --build

## Authentication

Recommended: on the **host**, run `claude setup-token`, put the value in
`.env` as `CLAUDE_CODE_OAUTH_TOKEN`. Otherwise authenticate interactively:

    cc-remote.py /path/to/folder login   # then type: /login

The login is stored in a shared docker volume (`cc-remote-claude-home`) and
persists across restarts and across projects.

## Firewall

By default only Anthropic's servers are reachable. To widen:
* add domains to `allowed-domains.txt`, or set `EXTRA_ALLOWED_DOMAINS` in `.env`
* set `ALLOW_ALL=true` in `.env` for full internet

## Ports

Set `PORTS=3000,8080` in `.env` (wrapper publishes them), or add a `ports:`
block to `docker-compose.yml`.

## Editing / git from the host

The folder is bind-mounted, so edit files and run `git` directly on the host —
it's the same working tree and `.git`. (Core git is path-independent; the
container just sees it at `/workspace`.) Avoid running mutating git commands on
the host and in the container at the same instant.
"""

SCAFFOLD = {
    "Dockerfile": DOCKERFILE,
    "entrypoint.sh": ENTRYPOINT,
    "init-firewall.sh": INIT_FIREWALL,
    "allowed-domains.txt": ALLOWED_DOMAINS,
    "docker-compose.yml": DOCKER_COMPOSE,
    "devcontainer.json": DEVCONTAINER_JSON,
    ".gitignore": GITIGNORE,
    "README.md": README,
}


# --------------------------------------------------------------------------- #
# Helpers
# --------------------------------------------------------------------------- #

def die(msg: str, code: int = 1):
    print(f"cc-remote: error: {msg}", file=sys.stderr)
    sys.exit(code)


def slugify(name: str) -> str:
    slug = re.sub(r"[^a-z0-9_.-]+", "-", name.lower()).strip("-.")
    return slug or "app"


def require_docker():
    if shutil.which("docker") is None:
        die("docker not found on PATH. Install Docker Desktop / Engine first.")
    if subprocess.run(["docker", "compose", "version"],
                      stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode != 0:
        die("`docker compose` is not available (need Docker Compose v2).")


def scaffold(devc: Path, project_name: str):
    devc.mkdir(parents=True, exist_ok=True)
    created = []
    for fname, content in SCAFFOLD.items():
        path = devc / fname
        if path.exists():
            continue
        path.write_text(content)
        if fname.endswith(".sh"):
            path.chmod(0o755)
        created.append(fname)
    if created:
        print(f"[cc-remote] scaffolded into {devc}: {', '.join(created)}")
    else:
        print(f"[cc-remote] setup files already present in {devc}")


def ensure_env(devc: Path, project_name: str, uid: int, gid: int):
    env = devc / ".env"
    if env.exists():
        return
    token = os.environ.get("CLAUDE_CODE_OAUTH_TOKEN", "")
    content = ENV_EXAMPLE.format(token=token, project_name=project_name, uid=uid, gid=gid)
    env.write_text(content)
    msg = "[cc-remote] created .env"
    if token:
        msg += " (picked up CLAUDE_CODE_OAUTH_TOKEN from environment)"
    else:
        msg += " — add CLAUDE_CODE_OAUTH_TOKEN or run the `login` command"
    print(msg)


def read_env(devc: Path) -> dict:
    """Tiny KEY=VALUE parser for our own .env."""
    env = {}
    f = devc / ".env"
    if not f.exists():
        return env
    for line in f.read_text().splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        k, v = line.split("=", 1)
        env[k.strip()] = v.strip()
    return env


def write_override(devc: Path, uid: int, gid: int):
    """Host-specific bits (uid/gid + published ports) live in the override file."""
    env = read_env(devc)
    ports = [p.strip() for p in env.get("PORTS", "").replace(",", " ").split() if p.strip()]
    lines = ["# Generated by cc-remote — host-specific overrides. Do not commit.",
             "services:", "  claude:", "    build:", "      args:",
             f"        USER_UID: \"{uid}\"", f"        USER_GID: \"{gid}\""]
    if ports:
        lines.append("    ports:")
        for p in ports:
            mapping = p if ":" in p else f"{p}:{p}"
            lines.append(f'      - "{mapping}"')
    (devc / "docker-compose.override.yml").write_text("\n".join(lines) + "\n")
    if ports:
        print(f"[cc-remote] publishing ports: {', '.join(ports)}")


def compose_cmd(devc: Path, project_slug: str, *args: str) -> list:
    base = ["docker", "compose", "-p", f"cc-remote-{project_slug}",
            "-f", str(devc / "docker-compose.yml")]
    override = devc / "docker-compose.override.yml"
    if override.exists():
        base += ["-f", str(override)]
    return base + list(args)


def run(cmd: list) -> int:
    print(f"[cc-remote] $ {' '.join(cmd)}")
    return subprocess.run(cmd).returncode


# --------------------------------------------------------------------------- #
# Commands
# --------------------------------------------------------------------------- #

def cmd_up(devc: Path, slug: str, build: bool):
    args = ["up", "-d"]
    if build:
        args.append("--build")
    if run(compose_cmd(devc, slug, *args)) != 0:
        die("failed to start the container.")
    print("\n[cc-remote] container is up. Following logs (Ctrl-C to detach)...")
    print("[cc-remote] Look for the session URL / QR code below, then open it in the Claude app.\n")
    run(compose_cmd(devc, slug, "logs", "-f"))


def cmd_down(devc: Path, slug: str):
    run(compose_cmd(devc, slug, "down"))


def cmd_logs(devc: Path, slug: str):
    run(compose_cmd(devc, slug, "logs", "-f"))


def cmd_shell(devc: Path, slug: str):
    run(compose_cmd(devc, slug, "exec", "claude", "bash"))


def cmd_login(devc: Path, slug: str):
    print("[cc-remote] opening Claude interactively — type /login, finish auth, then /exit.")
    # Run an interactive claude session as the claude user; bypass the default
    # remote-control CMD so you land in a normal prompt.
    rc = run(compose_cmd(devc, slug, "exec", "claude", "gosu", "claude", "claude"))
    if rc != 0:
        print("[cc-remote] is the container running? Try the `up` command first.")


def main():
    ap = argparse.ArgumentParser(
        prog="cc-remote.py",
        description="Run Claude Code Remote Control in a Docker container for a folder.")
    ap.add_argument("folder", help="path to the project folder")
    ap.add_argument("command", nargs="?", default="up",
                    choices=["up", "down", "logs", "login", "shell", "rebuild", "init"],
                    help="action (default: up)")
    args = ap.parse_args()

    folder = Path(args.folder).expanduser().resolve()
    if not folder.is_dir():
        die(f"not a directory: {folder}")

    project_name = slugify(folder.name)
    devc = folder / ".devcontainer"

    if args.command != "init":
        require_docker()

    uid = os.getuid() if hasattr(os, "getuid") else 1000
    gid = os.getgid() if hasattr(os, "getgid") else 1000

    # Always make sure scaffolding + host-specific files are current.
    scaffold(devc, project_name)
    ensure_env(devc, project_name, uid, gid)
    write_override(devc, uid, gid)

    if args.command == "init":
        print(f"[cc-remote] ready. Next: cc-remote.py {folder} up")
    elif args.command == "up":
        cmd_up(devc, project_name, build=True)
    elif args.command == "rebuild":
        run(compose_cmd(devc, project_name, "build", "--no-cache"))
        cmd_up(devc, project_name, build=False)
    elif args.command == "down":
        cmd_down(devc, project_name)
    elif args.command == "logs":
        cmd_logs(devc, project_name)
    elif args.command == "shell":
        cmd_shell(devc, project_name)
    elif args.command == "login":
        cmd_login(devc, project_name)


if __name__ == "__main__":
    main()
