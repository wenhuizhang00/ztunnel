#!/usr/bin/env bash
# =============================================================================
# ztunnel-testbed - Performance benchmark suite
# =============================================================================
#
# Architecture:
#   fortio-client pod  →  ztunnel  →  fortio-server pod   (ambient namespace)
#   fortio-client pod  →  fortio-server pod                (baseline namespace)
#
# Test matrix:
#   1. HTTP throughput & latency by payload size (64-1500B)
#   2. HTTP application benchmark (GET, no keep-alive, POST, burst)
#   3. Concurrency sweep (c=1..64)
#   4. ztunnel resource usage (CPU/memory during load)
#   5. Ambient vs baseline comparison table
#
# Uses fortio-client → fortio-server:8080 (dedicated server, not http-echo).
#
# Params (env vars):
#   MODE          - ambient | baseline | both (default: both)
#   CONCURRENCY   - concurrent connections (default: 4)
#   DURATION      - per-test duration (default: 20s)
#   REQUESTS      - total requests (default: 0 = use DURATION)
#   PACKET_SIZES  - payload sizes in bytes (default: 64,128,256,512,1024,1500)
#   OUTPUT_DIR    - results directory (default: .bench-results)
#   SKIP_SWEEP    - 1 to skip concurrency sweep (default: 0)
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
source "${PROJECT_ROOT}/scripts/common.sh"

MODE="${MODE:-both}"
CONCURRENCY="${CONCURRENCY:-4}"
DURATION="${DURATION:-20s}"
REQUESTS="${REQUESTS:-0}"
PACKET_SIZES="${PACKET_SIZES:-64,128,256,512,1024,1500}"
OUTPUT_DIR="${OUTPUT_DIR:-${PROJECT_ROOT}/.bench-results}"
SKIP_SWEEP="${SKIP_SWEEP:-0}"

mkdir -p "$OUTPUT_DIR"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
REPORT_FILE="${OUTPUT_DIR}/report-${TIMESTAMP}.txt"

ensure_kubectl_context

# --- Discover pods ---
find_fortio_client() {
  local ns="$1"
  kubectl get pods -n "$ns" -l app=fortio-client -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true
}

AMBIENT_CLIENT=$(find_fortio_client "$APP_NAMESPACE")
BASELINE_CLIENT=$(find_fortio_client "$APP_NAMESPACE_BASELINE")
AMBIENT_URL="http://fortio-server.${APP_NAMESPACE}.svc.cluster.local:8080/"
BASELINE_URL="http://fortio-server.${APP_NAMESPACE_BASELINE}.svc.cluster.local:8080/"

if [[ -z "$AMBIENT_CLIENT" ]] && [[ "$MODE" != "baseline" ]]; then
  log_error "fortio-client not found in ${APP_NAMESPACE}. Run: make deploy"
  exit 1
fi
if [[ -z "$BASELINE_CLIENT" ]] && [[ "$MODE" != "ambient" ]]; then
  log_error "fortio-client not found in ${APP_NAMESPACE_BASELINE}. Run: make deploy"
  exit 1
fi

# Verify fortio binary (no shell in distroless image -- call fortio directly)
verify_fortio() {
  local ns="$1" pod="$2"
  if ! kubectl exec -n "$ns" "$pod" -c fortio -- fortio version &>/dev/null; then
    log_error "fortio binary not working in $pod ($ns)"
    exit 1
  fi
}

[[ -n "$AMBIENT_CLIENT" ]] && verify_fortio "$APP_NAMESPACE" "$AMBIENT_CLIENT"
[[ -n "$BASELINE_CLIENT" ]] && verify_fortio "$APP_NAMESPACE_BASELINE" "$BASELINE_CLIENT"
FORTIO_VER=$(kubectl exec -n "$APP_NAMESPACE" "${AMBIENT_CLIENT:-$BASELINE_CLIENT}" -c fortio -- fortio version 2>/dev/null || echo "unknown")
log_ok "fortio clients ready (version: $FORTIO_VER)"

# Verify connectivity
verify_conn() {
  local ns="$1" pod="$2" url="$3"
  if ! kubectl exec -n "$ns" "$pod" -c fortio -- fortio curl "$url" &>/dev/null; then
    log_error "Cannot reach $url from $pod"
    kubectl exec -n "$ns" "$pod" -c fortio -- fortio curl "$url" 2>&1 | tail -3 || true
    exit 1
  fi
}

if [[ -n "$AMBIENT_CLIENT" ]] && [[ "$MODE" != "baseline" ]]; then
  verify_conn "$APP_NAMESPACE" "$AMBIENT_CLIENT" "$AMBIENT_URL"
fi
if [[ -n "$BASELINE_CLIENT" ]] && [[ "$MODE" != "ambient" ]]; then
  verify_conn "$APP_NAMESPACE_BASELINE" "$BASELINE_CLIENT" "$BASELINE_URL"
fi
log_ok "Connectivity OK"

# --- Run fortio and parse results ---
# Note: fortio/fortio is a distroless image (no shell, no cat, no tee).
# We capture output directly from kubectl exec's stdout/stderr.
run_and_report() {
  local label="$1" ns="$2" client_pod="$3" url="$4" conc="$5"
  shift 5

  # Build args array for kubectl exec -- fortio load ...
  local -a load_args=(fortio load -c "$conc" -qps 0)
  if [[ "$REQUESTS" -gt 0 ]]; then
    load_args+=(-n "$REQUESTS")
  else
    load_args+=(-t "$DURATION")
  fi
  # Append extra args (e.g. -payload-size 64 -content-type application/octet-stream)
  for arg in "$@"; do
    load_args+=($arg)
  done
  load_args+=("$url")

  # Run fortio and capture stdout+stderr directly from kubectl exec
  local raw
  raw=$(kubectl exec -n "$ns" "$client_pod" -c fortio -- "${load_args[@]}" 2>&1) || true

  if [[ -z "$raw" ]] || ! echo "$raw" | grep -q "All done"; then
    local err_msg
    err_msg=$(echo "$raw" | tail -3 | tr '\n' ' ')
    printf "  %-28s  %10s  %8s  %8s  %8s  %8s  %8s  %s\n" "$label" "ERROR" "-" "-" "-" "-" "-" "${err_msg:0:50}"
    return
  fi

  # Parse fortio text output
  local qps avg p50 p90 p99 p999 ok_pct

  qps=$(echo "$raw" | grep "All done" | grep -oE '[0-9]+\.[0-9]+ qps' | grep -oE '[0-9]+\.[0-9]+' || echo "N/A")
  avg=$(echo "$raw" | grep "All done" | grep -oE '[0-9]+\.[0-9e.-]+ avg' | grep -oE '[0-9]+\.[0-9e.-]+' || echo "N/A")
  p50=$(echo "$raw" | grep "target 50%" | awk '{print $NF}' || echo "N/A")
  p90=$(echo "$raw" | grep "target 90%" | awk '{print $NF}' || echo "N/A")
  p99=$(echo "$raw" | grep "target 99%" | grep -v "99.9" | awk '{print $NF}' || echo "N/A")
  p999=$(echo "$raw" | grep "target 99.9%" | awk '{print $NF}' || echo "N/A")
  ok_pct=$(echo "$raw" | grep "Code 200" | grep -oE '[0-9]+\.[0-9]+ %' | head -1 || echo "")

  to_ms() {
    local v="$1"
    [[ -z "$v" || "$v" == "N/A" ]] && echo "  N/A" && return
    awk "BEGIN {printf \"%7.3f\", $v * 1000}" 2>/dev/null || echo "  $v"
  }

  printf "  %-28s  %10s  %8s  %8s  %8s  %8s  %8s  %s\n" \
    "$label" "${qps:-N/A}" "$(to_ms "$avg")" "$(to_ms "$p50")" "$(to_ms "$p90")" "$(to_ms "$p99")" "$(to_ms "$p999")" "${ok_pct}"
}

print_header() {
  printf "  %-28s  %10s  %8s  %8s  %8s  %8s  %8s  %s\n" \
    "Test" "QPS" "Avg(ms)" "P50(ms)" "P90(ms)" "P99(ms)" "P99.9ms" "OK%"
  printf "  %-28s  %10s  %8s  %8s  %8s  %8s  %8s  %s\n" \
    "----------------------------" "----------" "--------" "--------" "--------" "--------" "--------" "------"
}

# --- Collect ztunnel resource usage ---
collect_ztunnel_stats() {
  local phase="$1"
  echo ""
  echo "  ztunnel resource usage ($phase):"
  local zt_stats
  zt_stats=$(kubectl top pods -n istio-system -l app=ztunnel --no-headers 2>/dev/null || echo "  (kubectl top not available - install metrics-server)")
  echo "$zt_stats" | while IFS= read -r line; do
    printf "    %s\n" "$line"
  done
}

# === Benchmark functions ===

bench_payload_sizes() {
  local mode="$1" ns="$2" client="$3" url="$4"
  echo ""
  echo "=================================================================="
  echo "  Throughput & Latency by Payload Size - POST ($mode)"
  echo "  Path: fortio-client → ${mode} → fortio-server"
  echo "  Concurrency: $CONCURRENCY, Duration: $DURATION"
  echo "=================================================================="
  echo ""
  print_header

  IFS=',' read -ra SIZES <<< "$PACKET_SIZES"
  for size in "${SIZES[@]}"; do
    log_step "BENCH" "[$mode ${size}B] POST payload=${size}B, c=$CONCURRENCY..." >&2
    run_and_report "${size}B POST" "$ns" "$client" "$url" "$CONCURRENCY" \
      -payload-size "$size" -content-type "application/octet-stream"
  done
}

bench_http_app() {
  local mode="$1" ns="$2" client="$3" url="$4"
  echo ""
  echo "=================================================================="
  echo "  HTTP Application Benchmark ($mode)"
  echo "  Path: fortio-client → ${mode} → fortio-server"
  echo "  Concurrency: $CONCURRENCY, Duration: $DURATION"
  echo "=================================================================="
  echo ""
  print_header

  log_step "BENCH" "[$mode] HTTP GET..." >&2
  run_and_report "HTTP GET" "$ns" "$client" "$url" "$CONCURRENCY"

  log_step "BENCH" "[$mode] HTTP GET (no keepalive)..." >&2
  run_and_report "GET (no keepalive)" "$ns" "$client" "$url" "$CONCURRENCY" -keepalive=false

  log_step "BENCH" "[$mode] HTTP POST 1KB..." >&2
  run_and_report "POST 1KB" "$ns" "$client" "$url" "$CONCURRENCY" \
    -payload-size 1024 -content-type "application/json"

  log_step "BENCH" "[$mode] HTTP GET burst c=32..." >&2
  run_and_report "GET burst (c=32)" "$ns" "$client" "$url" 32

  log_step "BENCH" "[$mode] HTTP GET burst c=64..." >&2
  run_and_report "GET burst (c=64)" "$ns" "$client" "$url" 64
}

bench_concurrency_sweep() {
  local mode="$1" ns="$2" client="$3" url="$4"
  echo ""
  echo "=================================================================="
  echo "  Concurrency Sweep ($mode)"
  echo "  Path: fortio-client → ${mode} → fortio-server"
  echo "  Duration: $DURATION"
  echo "=================================================================="
  echo ""
  print_header

  for conc in 1 2 4 8 16 32 64; do
    log_step "BENCH" "[$mode] c=$conc..." >&2
    run_and_report "c=$conc" "$ns" "$client" "$url" "$conc"
  done
}

# === Main execution ===
log_info "Performance benchmark suite"
log_info "  Architecture: fortio-client → ztunnel → fortio-server"
log_info "  MODE=$MODE  CONCURRENCY=$CONCURRENCY  DURATION=$DURATION  SIZES=$PACKET_SIZES"
log_info "  Report: $REPORT_FILE"

{
  echo "========================================================================"
  echo "  ztunnel-testbed Performance Report"
  echo "  Generated: $(date)"
  echo "  Cluster: $(kubectl config current-context 2>/dev/null || echo unknown)"
  echo "  Nodes: $(kubectl get nodes --no-headers 2>/dev/null | wc -l | tr -d ' ')"
  echo "  Architecture: fortio-client → ztunnel (mTLS) → fortio-server"
  echo "  Mode: $MODE  Concurrency: $CONCURRENCY  Duration: $DURATION"
  echo "  Packet sizes: $PACKET_SIZES"
  echo "========================================================================"

  run_mode() {
    local mode="$1" ns="$2" client="$3" url="$4"

    collect_ztunnel_stats "before $mode"

    bench_payload_sizes "$mode" "$ns" "$client" "$url"
    bench_http_app "$mode" "$ns" "$client" "$url"

    if [[ "$SKIP_SWEEP" != "1" ]]; then
      bench_concurrency_sweep "$mode" "$ns" "$client" "$url"
    fi

    collect_ztunnel_stats "after $mode"
  }

  suite_start=$(date +%s)

  if [[ "$MODE" == "ambient" ]]; then
    run_mode "ambient" "$APP_NAMESPACE" "$AMBIENT_CLIENT" "$AMBIENT_URL"
  elif [[ "$MODE" == "baseline" ]]; then
    run_mode "baseline" "$APP_NAMESPACE_BASELINE" "$BASELINE_CLIENT" "$BASELINE_URL"
  else
    run_mode "ambient" "$APP_NAMESPACE" "$AMBIENT_CLIENT" "$AMBIENT_URL"
    run_mode "baseline" "$APP_NAMESPACE_BASELINE" "$BASELINE_CLIENT" "$BASELINE_URL"

    echo ""
    echo "=================================================================="
    echo "  Summary: Ambient vs Baseline"
    echo "=================================================================="
    echo ""
    echo "  Compare QPS and P99 columns between ambient and baseline above."
    echo "  Ambient adds mTLS encryption via ztunnel HBONE tunnel."
    echo ""
    echo "  Typical overhead:"
    echo "    Latency:    +0.1-0.5ms P99 (mTLS handshake amortized over keep-alive)"
    echo "    Throughput: -5-15% (encryption/decryption overhead)"
    echo "    CPU:        ztunnel uses ~50-200m CPU per 10k QPS"
    echo ""
  fi

  suite_elapsed=$(( $(date +%s) - suite_start ))
  echo ""
  echo "Benchmark completed in ${suite_elapsed}s"

} 2>&1 | tee "$REPORT_FILE"

log_ok "Report saved to: $REPORT_FILE"
