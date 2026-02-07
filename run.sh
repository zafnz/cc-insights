#!/bin/bash

# Use $1 for DIR or ../ if not set.
DIR=${1:-../}
# Run the Flutter app in development mode
cd frontend && flutter run --dart-entrypoint-args="$DIR" -d macos
