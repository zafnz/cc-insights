#!/bin/bash
echo "initialising worktree..."
# Check if backend bundle exists, if not build it
if [ ! -f "backend-node/dist/bundle.js" ]; then
  echo "Backend bundle not found, building..."
  cd backend-node
  npm install
  npm run bundle
  cd ..
fi
# Check if git submodule packages/drag_split_layout are initialized
# Validate if the directory exists and is not empty
if [ ! -d "packages/drag_split_layout" ] || [ -z "$(ls -A packages/drag_split_layout)" ]; then
  echo "Submodule packages/drag_split_layout not found or empty, initializing..."
  git submodule update --init --recursive
fi

echo "initialisation complete."
