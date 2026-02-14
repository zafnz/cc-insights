#!/bin/bash

# Run the Flutter app in development mode.
# All arguments are forwarded to the Dart entrypoint.
# If no arguments are supplied, defaults to "../" (the project directory).

ENTRYPOINT_ARGS=()
HAS_STDOUT_LOG_LEVEL=false

for arg in "$@"; do
  if [ "$arg" = "--stdout-log-level" ]; then
    HAS_STDOUT_LOG_LEVEL=true
  fi
done

# Default --stdout-log-level to debug unless already supplied
if [ "$HAS_STDOUT_LOG_LEVEL" = false ]; then
  ENTRYPOINT_ARGS+=(--dart-entrypoint-args="--stdout-log-level")
  ENTRYPOINT_ARGS+=(--dart-entrypoint-args="debug")
fi

if [ $# -eq 0 ]; then
  ENTRYPOINT_ARGS+=(--dart-entrypoint-args="../")
else
  for arg in "$@"; do
    ENTRYPOINT_ARGS+=(--dart-entrypoint-args="$arg")
  done
fi

cd frontend && flutter run "${ENTRYPOINT_ARGS[@]}" -d macos
