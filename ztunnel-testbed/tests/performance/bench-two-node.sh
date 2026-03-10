#!/usr/bin/env bash
# =============================================================================
# Two-node cross-node benchmark
# =============================================================================
# Runs throughput and latency tests between two nodes in three paths:
#   1. Cross-node:  client (worker) → ztunnel HBONE → server (control-plane)
#   2. Reverse:     client (control-plane) → ztunnel HBONE → server (worker)
#   3. Same-node:   client (worker) → ztunnel (local) → server (worker)
#
# Comparing paths 1 vs 3 shows the cost of HBONE tunnel (cross-node overhead).
# Comparing paths 1 vs 2 shows directional asymmetry (if any).
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

NS="${APP_NAMESPACE:-grimlock}"

# Discover pods
CLI_WK=$(kubectl get pods -n "$NS" -l app=fortio-client-wk --field-selector=status.phase=Running -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
CLI_CP=$(kubectl get pods -n "$NS" -l app=fortio-client-cp --field-selector=status.phase=Running -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
SVR_CP_URL="http://fortio-server-cp.${NS}.svc.cluster.local:8080/"
SVR_WK_URL="http://fortio-server-wk.${NS}.svc.cluster.local:8080/"

if [[ -z "$CLI_WK" ]]; then
  log_error "fortio-client-wk not found. Run: make setup-two-node"
  exit 1
fi

# Get node info
CLI_WK_NODE=$(kubectl get pod "$CLI_WK" -n "$NS" -o jsonpath='{.spec.nodeName}' 2>/dev/null)
CLI_CP_NODE=$(kubectl get pod "${CLI_CP:-none}" -n "$NS" -o jsonpath='{.spec.nodeName}' 2>/dev/null || echo "N/A")
SVR_CP_NODE=$(kubectl get pods -n "$NS" -l app=fortio-server-cp -o jsonpath='{.items[0].spec.nodeName}' 2>/dev/null || echo "N/A")
SVR_WK_NODE=$(kubectl get pods -n "$NS" -l app=fortio-server-wk -o jsonpath='{.items[0].spec.nodeName}' 2>/dev/null || echo "N/A")

# Verify
kubectl exec -n "$NS" "$CLI_WK" -c fortio -- fortio version &>/dev/null || { log_error "fortio not working"; exit 1; }
kubectl exec -n "$NS" "$CLI_WK" -c fortio -- fortio curl "$SVR_CP_URL" &>/dev/null || { log_error "Cannot reach $SVR_CP_URL"; exit 1; }

log_ok "Two-node benchmark ready"
log_info "  Path 1 (cross-node): client on $CLI_WK_NODE → server on $SVR_CP_NODE"
log_info "  Path 2 (reverse):    client on $CLI_CP_NODE → server on $SVR_WK_NODE"
log_info "  Path 3 (same-node):  client on $CLI_WK_NODE → server on $SVR_WK_NODE"

REPORT_FILE="${OUTPUT_DIR}/two-node-${TIMESTAMP}.txt"

run_path_throughput() {
  local label="$1" ns="$2" client="$3" url="$4"
  echo ""
  echo "  --- $label ---"
  BENCH_TYPE="throughput"
  print_header

  IFS=',' read -ra SIZES <<< "$PACKET_SIZES"
  for size in "${SIZES[@]}"; do
    log_step "TPUT" "[$label ${size}B] c=$CONCURRENCY..." >&2
    run_and_report "${size}B POST" "$ns" "$client" "$url" "$CONCURRENCY" \
      -payload-size "$size" -content-type "application/octet-stream"
  done
}

run_path_latency() {
  local label="$1" ns="$2" client="$3" url="$4"
  echo ""
  echo "  --- $label ---"
  BENCH_TYPE="latency"
  print_header

  IFS=',' read -ra SIZES <<< "$PACKET_SIZES"
  for size in "${SIZES[@]}"; do
    log_step "LAT" "[$label ${size}B] c=1..." >&2
    run_and_report "${size}B POST" "$ns" "$client" "$url" 1 \
      -payload-size "$size" -content-type "application/octet-stream"
  done

  log_step "LAT" "[$label] GET c=1..." >&2
  run_and_report "GET c=1" "$ns" "$client" "$url" 1

  log_step "LAT" "[$label] GET no-ka c=1..." >&2
  run_and_report "GET no-ka c=1" "$ns" "$client" "$url" 1 -keepalive=false
}

{
  echo "========================================================================"
  echo "  TWO-NODE CROSS-NODE BENCHMARK"
  echo "  Generated: $(date)"
  echo "  Cluster: $(kubectl config current-context 2>/dev/null)"
  echo "  Path 1: $CLI_WK_NODE → $SVR_CP_NODE (cross-node, HBONE tunnel)"
  echo "  Path 2: $CLI_CP_NODE → $SVR_WK_NODE (reverse, HBONE tunnel)"
  echo "  Path 3: $CLI_WK_NODE → $SVR_WK_NODE (same-node, local ztunnel)"
  echo "  Duration: $DURATION  Concurrency: $CONCURRENCY"
  echo "  Packet sizes: $PACKET_SIZES"
  echo "========================================================================"

  collect_ztunnel_stats "before benchmark"

  # === THROUGHPUT ===
  echo ""
  echo "=================================================================="
  echo "  THROUGHPUT: Cross-node vs Same-node comparison"
  echo "  Measures max QPS. Compare cross-node overhead to same-node."
  echo "  Concurrency: $CONCURRENCY, Duration: $DURATION"
  echo "=================================================================="

  run_path_throughput "cross-node (worker→CP)" "$NS" "$CLI_WK" "$SVR_CP_URL"

  if [[ -n "$CLI_CP" ]]; then
    run_path_throughput "reverse (CP→worker)" "$NS" "$CLI_CP" "$SVR_WK_URL"
  fi

  run_path_throughput "same-node (worker→worker)" "$NS" "$CLI_WK" "$SVR_WK_URL"

  # === CONCURRENCY SWEEP ===
  if [[ "$SKIP_SWEEP" != "1" ]]; then
    echo ""
    echo "=================================================================="
    echo "  THROUGHPUT: Concurrency Sweep (cross-node)"
    echo "  Finds peak QPS between the two nodes."
    echo "=================================================================="
    echo ""
    BENCH_TYPE="throughput"
    print_header

    for conc in 1 4 8 16 32 64 128; do
      log_step "TPUT" "[cross-node] c=$conc..." >&2
      run_and_report "c=$conc" "$NS" "$CLI_WK" "$SVR_CP_URL" "$conc"
    done
  fi

  # === LATENCY ===
  echo ""
  echo "=================================================================="
  echo "  LATENCY: Cross-node vs Same-node comparison"
  echo "  Min/Avg/Max/P99 in microseconds. c=1 for accurate measurement."
  echo "  Compare cross-node HBONE overhead to same-node local path."
  echo "=================================================================="

  run_path_latency "cross-node (worker→CP)" "$NS" "$CLI_WK" "$SVR_CP_URL"

  if [[ -n "$CLI_CP" ]]; then
    run_path_latency "reverse (CP→worker)" "$NS" "$CLI_CP" "$SVR_WK_URL"
  fi

  run_path_latency "same-node (worker→worker)" "$NS" "$CLI_WK" "$SVR_WK_URL"

  collect_ztunnel_stats "after benchmark"

  echo ""
  echo "=================================================================="
  echo "  Notes:"
  echo "  • cross-node vs same-node difference = HBONE tunnel overhead"
  echo "  • cross-node vs reverse = directional asymmetry (should be similar)"
  echo "  • all paths go through ztunnel (ambient namespace, mTLS encrypted)"
  echo "=================================================================="
  echo ""
  echo "Benchmark complete."

} 2>&1 | tee "$REPORT_FILE"

log_ok "Report: $REPORT_FILE"
