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
#   test_desc "why..."  - Print 1-line explanation of what this test verifies
#   pass "msg"          - Green PASS with elapsed time
#   fail "msg"          - Red FAIL with elapsed time, returns exit code 1
#   skip "reason"       - Yellow SKIP (test exits 0, not counted as failure)
#   detail "info"       - Dimmed diagnostic line (pod names, IPs, counts)
#
# Exit code convention:
#   0 = all assertions passed (PASS or SKIP)
#   1 = at least one assertion failed (FAIL)
# =============================================================================

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
DIM='\033[2m'
WHITE='\033[1;37m'
NC='\033[0m'

_TEST_NAME=""
_TEST_START_TS=""

test_start() {
  _TEST_NAME="$*"
  _TEST_START_TS=$(date +%s%3N 2>/dev/null || date +%s)
  echo ""
  echo -e "${CYAN}>>> Test: ${_TEST_NAME}${NC}"
}

# test_desc "explanation" - prints a short description of what this test checks.
# Call right after test_start to explain the purpose on screen.
test_desc() {
  echo -e "    ${DIM}$*${NC}"
}

pass() {
  local elapsed=""
  if [[ -n "$_TEST_START_TS" ]]; then
    local now; now=$(date +%s%3N 2>/dev/null || date +%s)
    elapsed=" ${DIM}($(( now - _TEST_START_TS ))ms)${NC}"
  fi
  echo -e "    ${GREEN}PASS${NC}: $*${elapsed}"
}

fail() {
  local elapsed=""
  if [[ -n "$_TEST_START_TS" ]]; then
    local now; now=$(date +%s%3N 2>/dev/null || date +%s)
    elapsed=" ${DIM}($(( now - _TEST_START_TS ))ms)${NC}"
  fi
  echo -e "    ${RED}FAIL${NC}: $*${elapsed}"
  return 1
}

skip() {
  echo -e "    ${YELLOW}SKIP${NC}: $*"
}

detail() {
  echo -e "    ${DIM}  → $*${NC}"
}
