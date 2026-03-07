#!/usr/bin/env bash
# =============================================================================
# Test library - common helpers for functionality and performance tests
# =============================================================================
#
# Provides structured test output with colored status, timing, and details.
# Source this in every test script:
#   source "${SCRIPT_DIR}/../lib.sh"
#
# Functions:
#   test_start "name"   - Print test header, start timer
#   pass "msg"          - Green PASS with elapsed time
#   fail "msg"          - Red FAIL with elapsed time, returns exit code 1
#   skip "reason"       - Yellow SKIP (test exits 0, not counted as failure)
#   detail "info"       - Dimmed diagnostic line (pod names, IPs, counts)
#
# Exit code convention:
#   0 = all assertions passed (PASS or SKIP)
#   1 = at least one assertion failed (FAIL)
#
# The test runner (run-functionality-tests.sh) counts pass/fail from exit codes.
# =============================================================================

set -euo pipefail

# ANSI color codes for structured output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
DIM='\033[2m'
NC='\033[0m'

_TEST_NAME=""
_TEST_START_TS=""

# test_start "Test name" - prints the test header and starts the timer.
# Call at the beginning of every test script, before any assertions.
test_start() {
  _TEST_NAME="$*"
  _TEST_START_TS=$(date +%s%3N 2>/dev/null || date +%s)
  echo ""
  echo -e "${CYAN}>>> Test: ${_TEST_NAME}${NC}"
}

# pass "message" - records a successful assertion.
# Prints green PASS with the elapsed time since test_start.
pass() {
  local elapsed=""
  if [[ -n "$_TEST_START_TS" ]]; then
    local now; now=$(date +%s%3N 2>/dev/null || date +%s)
    elapsed=" ${DIM}($(( now - _TEST_START_TS ))ms)${NC}"
  fi
  echo -e "    ${GREEN}PASS${NC}: $*${elapsed}"
}

# fail "message" - records a failed assertion.
# Prints red FAIL with elapsed time and returns exit code 1.
# With set -e, this causes the test script to exit immediately.
fail() {
  local elapsed=""
  if [[ -n "$_TEST_START_TS" ]]; then
    local now; now=$(date +%s%3N 2>/dev/null || date +%s)
    elapsed=" ${DIM}($(( now - _TEST_START_TS ))ms)${NC}"
  fi
  echo -e "    ${RED}FAIL${NC}: $*${elapsed}"
  return 1
}

# skip "reason" - marks a test as skipped (precondition not met).
# Prints yellow SKIP. The test should then exit 0 (not a failure).
# Example: skip "No curl-client pod (run: make deploy)"; exit 0
skip() {
  echo -e "    ${YELLOW}SKIP${NC}: $*"
}

# detail "info" - prints a dimmed diagnostic line.
# Use for pod names, IP addresses, counts, response previews, etc.
# These help diagnose failures without re-running kubectl manually.
detail() {
  echo -e "    ${DIM}  → $*${NC}"
}
