#!/usr/bin/env bash
# =============================================================================
# ztunnel-testbed - Run all functionality tests
# =============================================================================

set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"
source "${PROJECT_ROOT}/tests/lib.sh"

ensure_kubectl_context

log_info "Running functionality tests..."

# Reset counters
TESTS_PASSED=0
TESTS_FAILED=0

for t in "${PROJECT_ROOT}/tests/functionality"/test-*.sh; do
  [[ -x "$t" ]] || chmod +x "$t"
  "$t" || true
done

test_summary
