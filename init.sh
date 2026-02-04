#!/bin/bash
echo "initialising worktree..."
cd frontend
echo "getting flutter packages..."
flutter pub get
cd ..
echo "initialisation complete."
