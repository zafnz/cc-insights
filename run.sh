#!/bin/bash

# Run the Flutter app in development mode.
# All arguments are forwarded to the Dart entrypoint.
# If no arguments are supplied, defaults to "../" (the project directory).

ENTRYPOINT_ARGS=()
if [ $# -eq 0 ]; then
  ENTRYPOINT_ARGS+=(--dart-entrypoint-args="../")
else
  for arg in "$@"; do
    ENTRYPOINT_ARGS+=(--dart-entrypoint-args="$arg")
  done
fi

cd frontend && flutter run "${ENTRYPOINT_ARGS[@]}" -d macos
