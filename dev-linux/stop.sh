#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
HASH="$(echo -n "$PROJECT_ROOT" | shasum | awk '{print substr($1,1,8)}')"
BASENAME="$(basename "$PROJECT_ROOT" | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9._-')"
CC_INSTANCE="cc-${BASENAME}-${HASH}"

export COMPOSE_PROJECT_NAME="$CC_INSTANCE"

CONTAINER="${CC_INSTANCE}-cc-linux-1"
RUNNING="$(docker inspect -f '{{.State.Running}}' "$CONTAINER" 2>/dev/null || echo "missing")"

if [ "$RUNNING" = "missing" ]; then
  echo "No container found: $CONTAINER"
  exit 0
fi

if [ "$RUNNING" = "true" ]; then
  echo "Stopping $CONTAINER..."
  # Try graceful stop first (5s), then force kill
  docker stop -t 5 "$CONTAINER" 2>/dev/null || docker kill "$CONTAINER" 2>/dev/null || true
else
  echo "Container already stopped."
fi

echo "Removing container..."
docker compose down --remove-orphans 2>/dev/null || true
echo "Stopped. Image and volumes preserved — run launch.sh to start again."
