#!/usr/bin/env bash
# =============================================================================
# ztunnel-testbed - Run performance tests
# =============================================================================
# Usage:
#   ./scripts/run-performance-tests.sh              # both ambient and baseline
#   MODE=ambient ./scripts/run-performance-tests.sh # ambient only
#   MODE=baseline ./scripts/run-performance-tests.sh
#   CONCURRENCY=8 REQUESTS=10000 ./scripts/run-performance-tests.sh
# =============================================================================

set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

ensure_kubectl_context

"${PROJECT_ROOT}/tests/performance/run-bench.sh" "$@"
