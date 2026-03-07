#!/usr/bin/env bash
# =============================================================================
# ztunnel-testbed - Performance benchmark suite (runs all benchmarks)
# =============================================================================
#
# Runs both throughput and latency benchmarks for the selected topology.
#
# Usage:
#   ./tests/performance/run-bench.sh                         # single-node, all
#   TOPOLOGY=cross-node ./tests/performance/run-bench.sh     # multi-node
#   BENCH=throughput ./tests/performance/run-bench.sh        # throughput only
#   BENCH=latency ./tests/performance/run-bench.sh           # latency only
#
# Params: MODE, CONCURRENCY, DURATION, PACKET_SIZES, TOPOLOGY, BENCH, SKIP_SWEEP
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

BENCH="${BENCH:-all}"
TOPOLOGY="${TOPOLOGY:-local}"

# Auto-detect topology if not explicitly set
if [[ "$TOPOLOGY" == "local" ]]; then
  node_count=$(kubectl get nodes --no-headers 2>/dev/null | wc -l | tr -d ' ')
  if [[ "${node_count:-1}" -ge 2 ]]; then
    # Check if cross-node fortio pods exist
    if kubectl get svc fortio-server-node2 -n "${APP_NAMESPACE:-grimlock}" &>/dev/null 2>&1; then
      TOPOLOGY="cross-node"
      echo "[INFO] Multi-node cluster detected with cross-node pods. Using TOPOLOGY=cross-node"
    fi
  fi
fi

export TOPOLOGY

if [[ "$BENCH" == "throughput" ]] || [[ "$BENCH" == "all" ]]; then
  "${SCRIPT_DIR}/bench-throughput.sh" "$@"
fi

if [[ "$BENCH" == "latency" ]] || [[ "$BENCH" == "all" ]]; then
  "${SCRIPT_DIR}/bench-latency.sh" "$@"
fi

if [[ "$BENCH" == "all" ]]; then
  echo ""
  echo "========================================================================"
  echo "  All benchmarks complete."
  echo "  Reports in: ${OUTPUT_DIR:-${PROJECT_ROOT}/.bench-results}/"
  echo "========================================================================"
fi
