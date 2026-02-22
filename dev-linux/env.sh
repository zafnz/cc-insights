#!/bin/sh
set -eu

# Works for bash + zsh
SCRIPT_PATH="$0"
# If sourced, $0 is your shell; so fall back to pwd of this file via a trick:
# Use the directory of the file being sourced when possible.
# In zsh, ${(%):-%x} expands to the sourced file path.
if [ -n "${ZSH_VERSION:-}" ]; then
  SCRIPT_PATH="${(%):-%x}"
elif [ -n "${BASH_VERSION:-}" ]; then
  SCRIPT_PATH="${BASH_SOURCE[0]}"
fi

SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_PATH")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

export CC_PROJECT_PATH="$PROJECT_ROOT"
HASH="$(echo -n "$PROJECT_ROOT" | shasum | awk '{print substr($1,1,8)}')"
BASENAME="$(basename "$PROJECT_ROOT" | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9._-')"
export CC_INSTANCE="cc-${BASENAME}-${HASH}"
export COMPOSE_PROJECT_NAME="$CC_INSTANCE"