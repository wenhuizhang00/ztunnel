#!/usr/bin/env bash
# =============================================================================
# Latency benchmark
# =============================================================================
# Measures P50/P90/P99/P99.9 latency in microseconds for varying payload
# sizes, connection types, and concurrency levels.
#
# Single-node:  fortio-client → ztunnel (local) → fortio-server
# Multi-node:   fortio-client (node1) → ztunnel HBONE → fortio-server (node2)
#
# Usage:
#   ./tests/performance/bench-latency.sh                     # single-node
#   TOPOLOGY=cross-node ./tests/performance/bench-latency.sh # cross-node
#   MODE=ambient CONCURRENCY=1 ./tests/performance/bench-latency.sh
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
source "${PROJECT_ROOT}/scripts/common.sh"
source "${PROJECT_ROOT}/tests/performance/bench-common.sh"

TOPOLOGY="${TOPOLOGY:-local}"
BENCH_TYPE="latency"

# For latency tests, use lower concurrency by default to measure true latency
[[ "${CONCURRENCY}" == "4" ]] && CONCURRENCY=1

log_info "Latency benchmark (topology=$TOPOLOGY, mode=$MODE, c=$CONCURRENCY)"

run_latency() {
  local mode="$1" ns="$2" client="$3" url="$4" topo_label="$5"

  echo ""
  echo "=================================================================="
  echo "  LATENCY: Payload Size ($mode, $topo_label)"
  echo "  Path: $client → $topo_label → fortio-server"
  echo "  Concurrency: $CONCURRENCY (low for accurate latency), Duration: $DURATION"
  echo "=================================================================="
  echo ""
  print_header

  IFS=',' read -ra SIZES <<< "$PACKET_SIZES"
  for size in "${SIZES[@]}"; do
    log_step "LAT" "[$mode/$topo_label ${size}B] c=$CONCURRENCY..." >&2
    run_and_report "${size}B POST" "$ns" "$client" "$url" "$CONCURRENCY" \
      -payload-size "$size" -content-type "application/octet-stream"
  done

  echo ""
  echo "=================================================================="
  echo "  LATENCY: HTTP Methods ($mode, $topo_label)"
  echo "=================================================================="
  echo ""
  print_header

  log_step "LAT" "[$mode/$topo_label] GET c=1..." >&2
  run_and_report "GET (c=1)" "$ns" "$client" "$url" 1

  log_step "LAT" "[$mode/$topo_label] GET c=1 no-ka..." >&2
  run_and_report "GET no-keepalive (c=1)" "$ns" "$client" "$url" 1 -keepalive=false

  log_step "LAT" "[$mode/$topo_label] POST 1KB c=1..." >&2
  run_and_report "POST 1KB (c=1)" "$ns" "$client" "$url" 1 \
    -payload-size 1024 -content-type "application/json"

  log_step "LAT" "[$mode/$topo_label] GET c=4..." >&2
  run_and_report "GET (c=4)" "$ns" "$client" "$url" 4

  log_step "LAT" "[$mode/$topo_label] GET c=16..." >&2
  run_and_report "GET (c=16)" "$ns" "$client" "$url" 16

  log_step "LAT" "[$mode/$topo_label] GET c=64..." >&2
  run_and_report "GET (c=64)" "$ns" "$client" "$url" 64
}

{
  print_report_header "LATENCY" "$TOPOLOGY"

  suite_start=$(date +%s)

  if [[ "$TOPOLOGY" == "cross-node" ]]; then
    resolve_cross_node_pods
    collect_ztunnel_stats "before latency"

    if [[ "$MODE" != "baseline" ]]; then
      run_latency "ambient" "$APP_NAMESPACE" "$CROSS_CLIENT" "$CROSS_URL_REMOTE" "cross-node"
    fi

    # Same-node for comparison
    run_latency "same-node" "$APP_NAMESPACE" "$CROSS_CLIENT" "$CROSS_URL_LOCAL" "same-node"

    collect_ztunnel_stats "after latency"
  else
    collect_ztunnel_stats "before latency"

    if [[ "$MODE" != "baseline" ]] && [[ -n "$AMBIENT_CLIENT" ]]; then
      run_latency "ambient" "$APP_NAMESPACE" "$AMBIENT_CLIENT" "$AMBIENT_URL" "single-node"
    fi
    if [[ "$MODE" != "ambient" ]] && [[ -n "$BASELINE_CLIENT" ]]; then
      run_latency "baseline" "$APP_NAMESPACE_BASELINE" "$BASELINE_CLIENT" "$BASELINE_URL" "single-node"
    fi

    collect_ztunnel_stats "after latency"
  fi

  suite_elapsed=$(( $(date +%s) - suite_start ))
  echo ""
  echo "Latency benchmark completed in ${suite_elapsed}s"

} 2>&1 | tee "$REPORT_FILE"

log_ok "Report: $REPORT_FILE"
