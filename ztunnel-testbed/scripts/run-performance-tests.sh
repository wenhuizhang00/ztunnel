#!/usr/bin/env bash
# =============================================================================
# ztunnel-testbed - Run performance tests
# =============================================================================
# Usage:
#   ./scripts/run-performance-tests.sh              # interactive menu
#   ./scripts/run-performance-tests.sh --all        # run all (non-interactive)
#   BENCH=throughput ./scripts/run-performance-tests.sh  # throughput only
#   BENCH=latency ./scripts/run-performance-tests.sh     # latency only
#   TOPOLOGY=cross-node ./scripts/run-performance-tests.sh  # multi-node
# =============================================================================

set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

BENCH="${BENCH:-${1:-}}"

# Interactive menu when no args and terminal is interactive
if [[ -z "$BENCH" ]] && [[ -t 0 ]] && [[ -t 1 ]]; then
  # Detect cluster topology
  node_count=$(kubectl get nodes --no-headers 2>/dev/null | wc -l | tr -d ' ')
  has_cross=$(kubectl get svc fortio-server-node2 -n "${APP_NAMESPACE:-grimlock}" -o name 2>/dev/null || true)

  echo ""
  echo -e "${BLUE}Performance Benchmarks${NC}"
  echo "─────────────────────────────────────────"
  echo ""
  echo "  Cluster: $(kubectl config current-context 2>/dev/null || echo unknown) ($node_count node(s))"
  echo ""
  echo "  Single-node tests:"
  echo "    1) Throughput test (payload sizes + concurrency sweep)"
  echo "    2) Latency test (average of P99 in microseconds)"
  echo "    3) Both throughput + latency"
  echo ""

  if [[ -n "$has_cross" ]]; then
    echo "  Cross-node tests (multi-node):"
    echo "    4) Throughput test (cross-node HBONE tunnel)"
    echo "    5) Latency test (cross-node HBONE tunnel)"
    echo "    6) Both throughput + latency (cross-node)"
    echo ""
  fi

  echo "  Comparison:"
  echo "    7) Ambient only (all benchmarks)"
  echo "    8) Baseline only (all benchmarks)"
  echo "    9) Quick benchmark (5s per test, skip sweep)"
  echo ""
  echo "    0) Run ALL benchmarks (auto-detect topology)"
  echo ""

  read -rp "Select benchmark [0-9]: " selection

  case "$selection" in
    1) BENCH=throughput; export TOPOLOGY=local ;;
    2) BENCH=latency; export TOPOLOGY=local ;;
    3) BENCH=all; export TOPOLOGY=local ;;
    4) BENCH=throughput; export TOPOLOGY=cross-node ;;
    5) BENCH=latency; export TOPOLOGY=cross-node ;;
    6) BENCH=all; export TOPOLOGY=cross-node ;;
    7) BENCH=all; export MODE=ambient ;;
    8) BENCH=all; export MODE=baseline ;;
    9) BENCH=all; export DURATION=5s; export SKIP_SWEEP=1 ;;
    0|"") BENCH=all ;;
    --all) BENCH=all ;;
    *)
      log_error "Invalid selection: $selection"
      exit 1
      ;;
  esac
fi

# Default to all
BENCH="${BENCH:-all}"
[[ "$BENCH" == "--all" ]] && BENCH=all

export BENCH

ensure_kubectl_context

"${PROJECT_ROOT}/tests/performance/run-bench.sh" "$@"
