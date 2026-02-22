#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
export CC_PROJECT_PATH="$PROJECT_ROOT"

HASH="$(echo -n "$PROJECT_ROOT" | shasum | awk '{print substr($1,1,8)}')"
BASENAME="$(basename "$PROJECT_ROOT" | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9._-')"
export CC_INSTANCE="cc-${BASENAME}-${HASH}"
export COMPOSE_PROJECT_NAME="$CC_INSTANCE"

FLUTTER_VERSION="${FLUTTER_VERSION:-$(flutter --version --machine | jq -r .frameworkVersion)}"
if [ -z "$FLUTTER_VERSION" ] || [ "$FLUTTER_VERSION" = "null" ]; then
  echo "Flutter or jq not installed, or version detection failed."
  exit 1
fi

export FLUTTER_VERSION
export FLUTTER_CHANNEL="${FLUTTER_CHANNEL:-stable}"

CONTAINER="${CC_INSTANCE}-cc-linux-1"

# Check if the container exists and is running
RUNNING="$(docker inspect -f '{{.State.Running}}' "$CONTAINER" 2>/dev/null || echo "missing")"

if [ "$RUNNING" = "true" ]; then
  echo "Container already running: $CONTAINER"
else
  # Remove stopped/dead container so compose can recreate cleanly
  if [ "$RUNNING" != "missing" ]; then
    echo "Container exists but not running (state: $RUNNING). Recreating..."
    docker compose down 2>/dev/null || true
  fi
  docker compose up --build -d
fi

HOSTPORT="$(docker compose port cc-linux 14500 | awk -F: '{print $2}' | tail -n 1)"

echo ""
echo "Instance: $CC_INSTANCE"
echo "Mounted:  $CC_PROJECT_PATH"
echo "Flutter:  $FLUTTER_VERSION ($FLUTTER_CHANNEL)"
echo "Logs:     $CC_PROJECT_PATH/.cc-insights-logs/$CC_INSTANCE/"
echo "Open:     http://localhost:$HOSTPORT"
