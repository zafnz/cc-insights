#!/bin/bash
set -euo pipefail

# This script runs INSIDE the Docker container — do not run on the host.
if [ ! -f /.dockerenv ]; then
  echo "ERROR: This script must run inside the Docker container." >&2
  echo "Use launch.sh to start the container." >&2
  exit 1
fi

INSTANCE="${CC_INSTANCE:-cc-linux}"
LOG_DIR="/workspace/.cc-insights-logs/${INSTANCE}"
mkdir -p "$LOG_DIR"

START_LOG="$LOG_DIR/start.log"
FLUTTER_LOG="$LOG_DIR/flutter.log"

{
  echo "== start.sh =="
  date
  echo "whoami: $(whoami)"
  echo "pwd: $(pwd)"
  echo "CC_INSTANCE: ${CC_INSTANCE:-}"
  echo "DISPLAY: ${DISPLAY:-unset}"
  echo "Flutter version:"
  flutter --version || true
} >>"$START_LOG" 2>&1

# Run Flutter in a tmux session so hot-reload.sh can send keys.
# Uses remain-on-exit so the session survives if Flutter quits — restart with:
#   docker exec <container> tmux respawn-pane -t flutter -k
tmux new-session -d -s flutter
tmux set-option -t flutter remain-on-exit on
tmux send-keys -t flutter \
  "cd /workspace/frontend && flutter pub get && flutter run -d linux 2>&1 | tee -a $LOG_DIR/flutter.log" Enter

touch "$START_LOG" "$FLUTTER_LOG"
tail -F "$START_LOG" "$FLUTTER_LOG"
