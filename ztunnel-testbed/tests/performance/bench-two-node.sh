#!/usr/bin/env bash
# =============================================================================
# Two-node cross-node benchmark
# =============================================================================
# Runs throughput and latency tests between two specific nodes:
#   Client: worker node (10.136.0.75)  → ztunnel HBONE → Server: control-plane (10.200.15.195)
#
# Uses fortio-client-wk (on worker) → fortio-server-cp (on control-plane)
#
# Usage:
#   ./tests/performance/bench-two-node.sh
#   DURATION=30s ./tests/performance/bench-two-node.sh
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
source "${PROJECT_ROOT}/scripts/common.sh"

BENCH_TYPE="two-node"
source "${PROJECT_ROOT}/tests/performance/bench-common.sh"

CP_IP="${CONTROL_PLANE_IP:-10.200.15.195}"
WK_IP="${WORKER_IP:-10.136.0.75}"
NS="${APP_NAMESPACE:-grimlock}"

# Find the two-node pods
CLIENT_POD=$(kubectl get pods -n "$NS" -l app=fortio-client-wk -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
SERVER_POD=$(kubectl get pods -n "$NS" -l app=fortio-server-cp -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
TARGET_URL="http://fortio-server-cp.${NS}.svc.cluster.local:8080/"

if [[ -z "$CLIENT_POD" ]] || [[ -z "$SERVER_POD" ]]; then
  log_error "Two-node test pods not found. Run: ./scripts/setup-two-node-test.sh deploy"
  exit 1
fi

CLIENT_NODE=$(kubectl get pod "$CLIENT_POD" -n "$NS" -o jsonpath='{.spec.nodeName}' 2>/dev/null)
SERVER_NODE=$(kubectl get pod "$SERVER_POD" -n "$NS" -o jsonpath='{.spec.nodeName}' 2>/dev/null)

# Verify fortio
kubectl exec -n "$NS" "$CLIENT_POD" -c fortio -- fortio version &>/dev/null || { log_error "fortio not working in $CLIENT_POD"; exit 1; }

# Verify connectivity
kubectl exec -n "$NS" "$CLIENT_POD" -c fortio -- fortio curl "$TARGET_URL" &>/dev/null || { log_error "Cannot reach $TARGET_URL"; exit 1; }

log_ok "Two-node benchmark ready"
log_info "  Client: $CLIENT_POD on $CLIENT_NODE ($WK_IP)"
log_info "  Server: $SERVER_POD on $SERVER_NODE ($CP_IP)"
log_info "  Path: worker → ztunnel HBONE → control-plane"

REPORT_FILE="${OUTPUT_DIR}/two-node-${TIMESTAMP}.txt"

{
  echo "========================================================================"
  echo "  TWO-NODE CROSS-NODE BENCHMARK"
  echo "  Generated: $(date)"
  echo "  Client: $CLIENT_NODE ($WK_IP) → Server: $SERVER_NODE ($CP_IP)"
  echo "  Path: fortio-client-wk → ztunnel HBONE tunnel → fortio-server-cp"
  echo "  Duration: $DURATION  Concurrency: $CONCURRENCY"
  echo "  Packet sizes: $PACKET_SIZES"
  echo "========================================================================"

  collect_ztunnel_stats "before two-node benchmark"

  # --- Throughput: payload sizes ---
  echo ""
  echo "=================================================================="
  echo "  THROUGHPUT: Payload Size Sweep (cross-node)"
  echo "  Client ($WK_IP) → ztunnel HBONE → Server ($CP_IP)"
  echo "  Measures max QPS between the two nodes."
  echo "  Concurrency: $CONCURRENCY, Duration: $DURATION"
  echo "=================================================================="
  echo ""
  BENCH_TYPE="throughput"
  print_header

  IFS=',' read -ra SIZES <<< "$PACKET_SIZES"
  for size in "${SIZES[@]}"; do
    log_step "TPUT" "[cross-node ${size}B] c=$CONCURRENCY..." >&2
    run_and_report "${size}B POST" "$NS" "$CLIENT_POD" "$TARGET_URL" "$CONCURRENCY" \
      -payload-size "$size" -content-type "application/octet-stream"
  done

  # --- Throughput: concurrency sweep ---
  if [[ "$SKIP_SWEEP" != "1" ]]; then
    echo ""
    echo "=================================================================="
    echo "  THROUGHPUT: Concurrency Sweep (cross-node)"
    echo "  Finds peak throughput between the two nodes."
    echo "=================================================================="
    echo ""
    print_header

    for conc in 1 4 8 16 32 64 128; do
      log_step "TPUT" "[cross-node] c=$conc..." >&2
      run_and_report "c=$conc" "$NS" "$CLIENT_POD" "$TARGET_URL" "$conc"
    done
  fi

  # --- Latency ---
  echo ""
  echo "=================================================================="
  echo "  LATENCY: Cross-node (client $WK_IP → server $CP_IP)"
  echo "  Measures round-trip latency through ztunnel HBONE tunnel."
  echo "  Min/Avg/Max/P99 in microseconds."
  echo "  Concurrency: 1 (for accurate single-request latency)"
  echo "=================================================================="
  echo ""
  BENCH_TYPE="latency"
  print_header

  for size in "${SIZES[@]}"; do
    log_step "LAT" "[cross-node ${size}B] c=1..." >&2
    run_and_report "${size}B POST" "$NS" "$CLIENT_POD" "$TARGET_URL" 1 \
      -payload-size "$size" -content-type "application/octet-stream"
  done

  log_step "LAT" "[cross-node] GET c=1..." >&2
  run_and_report "GET c=1" "$NS" "$CLIENT_POD" "$TARGET_URL" 1

  log_step "LAT" "[cross-node] GET no-keepalive c=1..." >&2
  run_and_report "GET no-ka c=1" "$NS" "$CLIENT_POD" "$TARGET_URL" 1 -keepalive=false

  log_step "LAT" "[cross-node] GET c=4..." >&2
  run_and_report "GET c=4" "$NS" "$CLIENT_POD" "$TARGET_URL" 4

  log_step "LAT" "[cross-node] GET c=16..." >&2
  run_and_report "GET c=16" "$NS" "$CLIENT_POD" "$TARGET_URL" 16

  log_step "LAT" "[cross-node] GET c=64..." >&2
  run_and_report "GET c=64" "$NS" "$CLIENT_POD" "$TARGET_URL" 64

  collect_ztunnel_stats "after two-node benchmark"

  echo ""
  echo "Benchmark complete."

} 2>&1 | tee "$REPORT_FILE"

log_ok "Report: $REPORT_FILE"
