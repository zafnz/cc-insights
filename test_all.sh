#!/bin/bash
set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
BOLD='\033[1m'
RESET='\033[0m'

REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"

pass() { echo -e "${GREEN}PASS${RESET} $1"; }
fail() { echo -e "${RED}FAIL${RESET} $1"; exit 1; }
section() { echo -e "\n${BOLD}=== $1 ===${RESET}\n"; }

# --- SDK Tests ---
section "claude_dart_sdk unit tests"
cd "$REPO_ROOT/claude_dart_sdk"
flutter test || fail "claude_dart_sdk unit tests"
pass "claude_dart_sdk unit tests"

# --- Frontend Unit/Widget Tests ---
section "Frontend unit/widget tests"
cd "$REPO_ROOT/frontend"
flutter test || fail "Frontend unit/widget tests"
pass "Frontend unit/widget tests"

# --- Frontend Integration Tests (one by one) ---
section "Frontend integration tests"
for test_file in "$REPO_ROOT/frontend/integration_test"/*_test.dart; do
  name="$(basename "$test_file")"
  echo -e "${BOLD}Running integration test: ${name}${RESET}"
  cd "$REPO_ROOT/frontend"
  flutter test "$test_file" || fail "Integration test: $name"
  pass "Integration test: $name"
done

# --- Summary ---
echo ""
section "All tests passed"
