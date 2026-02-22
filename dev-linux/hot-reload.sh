#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
HASH="$(echo -n "$PROJECT_ROOT" | shasum | awk '{print substr($1,1,8)}')"
BASENAME="$(basename "$PROJECT_ROOT" | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9._-')"
CC_INSTANCE="cc-${BASENAME}-${HASH}"

export COMPOSE_PROJECT_NAME="$CC_INSTANCE"

docker compose exec -T cc-linux tmux send-keys -t flutter r
