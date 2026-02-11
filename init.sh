#!/bin/bash
echo "initialising worktree..."

# Get the directory of the script
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$SCRIPT_DIR"

pub_directories=(
  "claude_dart_sdk"
  "codex_dart_sdk"
  "agent_dart_sdk"
  "frontend"
)

for dir in "${pub_directories[@]}"; do
echo "Running flutter pub get in $dir..."
cd "$SCRIPT_DIR/$dir"
flutter pub get
done

cd $SCRIPT_DIR
echo "initialisation complete."
