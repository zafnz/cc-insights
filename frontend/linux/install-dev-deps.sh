#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LIST="$SCRIPT_DIR/dev-deps.apt.txt"

if ! command -v apt-get >/dev/null 2>&1; then
  echo "This script requires apt-get (Debian/Ubuntu)."
  exit 1
fi

echo "Installing Linux development dependencies..."
sudo apt-get update
sudo apt-get install -y --no-install-recommends $(sed -e 's/#.*//' -e '/^[[:space:]]*$/d' "$LIST" | tr '\n' ' ')

echo ""
echo "Done."