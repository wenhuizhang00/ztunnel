#!/usr/bin/env bash
# =============================================================================
# Test library - common helpers for functionality and performance tests
# =============================================================================

set -euo pipefail

TESTS_PASSED=0
TESTS_FAILED=0

test_start() {
  echo ""
  echo ">>> Test: $*"
}

pass() {
  echo "    PASS: $*"
  ((TESTS_PASSED++)) || true
}

fail() {
  echo "    FAIL: $*"
  ((TESTS_FAILED++)) || true
  return 1
}

test_summary() {
  echo ""
  echo "=========================================="
  echo "Summary: $TESTS_PASSED passed, $TESTS_FAILED failed"
  echo "=========================================="
  [[ $TESTS_FAILED -eq 0 ]]
}
