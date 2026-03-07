#!/usr/bin/env bash
# =============================================================================
# Throughput benchmark
# =============================================================================
# Measures maximum QPS (queries per second) for varying payload sizes
# and concurrency levels. Focuses on raw throughput capacity.
#
# Single-node:  fortio-client → ztunnel (local) → fortio-server
# Multi-node:   fortio-client (node1) → ztunnel HBONE → fortio-server (node2)
#
# Usage:
#   ./tests/performance/bench-throughput.sh                  # single-node
#   TOPOLOGY=cross-node ./tests/performance/bench-throughput.sh  # cross-node
#   MODE=ambient CONCURRENCY=64 ./tests/performance/bench-throughput.sh
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
source "${PROJECT_ROOT}/scripts/common.sh"
source "${PROJECT_ROOT}/tests/performance/bench-common.sh"

TOPOLOGY="${TOPOLOGY:-local}"
BENCH_TYPE="throughput"

log_info "Throughput benchmark (topology=$TOPOLOGY, mode=$MODE)"

run_throughput() {
  local mode="$1" ns="$2" client="$3" url="$4" topo_label="$5"

  echo ""
  echo "=================================================================="
  echo "  THROUGHPUT: Payload Size Sweep ($mode, $topo_label)"
  echo "  Measures maximum QPS for POST requests with varying body sizes."
  echo "  Higher QPS = better throughput. Compare ambient vs baseline."
  echo "  Path: $client → $topo_label → fortio-server"
  echo "  Concurrency: $CONCURRENCY, Duration: $DURATION"
  echo "=================================================================="
  echo ""
  print_header

  IFS=',' read -ra SIZES <<< "$PACKET_SIZES"
  for size in "${SIZES[@]}"; do
    log_step "TPUT" "[$mode/$topo_label ${size}B] c=$CONCURRENCY..." >&2
    run_and_report "${size}B POST" "$ns" "$client" "$url" "$CONCURRENCY" \
      -payload-size "$size" -content-type "application/octet-stream"
  done

  if [[ "$SKIP_SWEEP" != "1" ]]; then
    echo ""
    echo "=================================================================="
    echo "  THROUGHPUT: Concurrency Sweep ($mode, $topo_label)"
    echo "  Increases concurrent connections to find peak QPS and saturation point."
    echo "=================================================================="
    echo ""
    print_header

    for conc in 1 4 8 16 32 64 128; do
      log_step "TPUT" "[$mode/$topo_label] c=$conc..." >&2
      run_and_report "c=$conc" "$ns" "$client" "$url" "$conc"
    done
  fi
}

{
  print_report_header "THROUGHPUT" "$TOPOLOGY"

  suite_start=$(date +%s)

  if [[ "$TOPOLOGY" == "cross-node" ]]; then
    # Multi-node: client on node1, server on node2
    resolve_cross_node_pods
    collect_ztunnel_stats "before throughput"

    if [[ "$MODE" != "baseline" ]]; then
      run_throughput "ambient" "$APP_NAMESPACE" "$CROSS_CLIENT" "$CROSS_URL_REMOTE" "cross-node"
    fi

    # Same-node baseline for comparison
    if [[ "$MODE" != "ambient" ]] || [[ "$MODE" == "both" ]]; then
      run_throughput "same-node" "$APP_NAMESPACE" "$CROSS_CLIENT" "$CROSS_URL_LOCAL" "same-node"
    fi

    collect_ztunnel_stats "after throughput"
  else
    # Single-node: standard fortio-client → fortio-server (same node)
    collect_ztunnel_stats "before throughput"

    if [[ "$MODE" != "baseline" ]] && [[ -n "$AMBIENT_CLIENT" ]]; then
      run_throughput "ambient" "$APP_NAMESPACE" "$AMBIENT_CLIENT" "$AMBIENT_URL" "single-node"
    fi
    if [[ "$MODE" != "ambient" ]] && [[ -n "$BASELINE_CLIENT" ]]; then
      run_throughput "baseline" "$APP_NAMESPACE_BASELINE" "$BASELINE_CLIENT" "$BASELINE_URL" "single-node"
    fi

    collect_ztunnel_stats "after throughput"
  fi

  suite_elapsed=$(( $(date +%s) - suite_start ))
  echo ""
  echo "Throughput benchmark completed in ${suite_elapsed}s"

} 2>&1 | tee "$REPORT_FILE"

log_ok "Report: $REPORT_FILE"
