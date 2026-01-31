#!/bin/bash

# Check if backend bundle exists, if not build it
if [ ! -f "backend-node/dist/bundle.js" ]; then
  echo "Backend bundle not found, building..."
  cd backend-node
  npm install
  npm run bundle
  cd ..
fi

cd frontend && flutter run --dart-entrypoint-args="../" -d macos

