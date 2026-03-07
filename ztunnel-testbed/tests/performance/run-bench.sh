#!/usr/bin/env bash
# =============================================================================
# ztunnel-testbed - Performance benchmark suite
# =============================================================================
# Comprehensive throughput and latency benchmarks for ztunnel ambient mode.
#
# Test matrix:
#   1. Throughput by payload size (64, 128, 256, 512, 1024, 1500 bytes)
#   2. P99 latency by payload size
#   3. HTTP application-level benchmark (GET, no keep-alive, POST, burst)
#   4. Ambient vs baseline comparison
#   5. Optional concurrency sweep
#
# Uses fortio for all load generation.
#
# Params (env vars):
#   MODE          - ambient | baseline | both (default: both)
#   CONCURRENCY   - concurrent connections (default: 4)
#   DURATION      - per-test duration (default: 15s)
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

FORTIO_POD=$(kubectl get pods -n "${APP_NAMESPACE}" -l app=fortio -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
if [[ -z "$FORTIO_POD" ]]; then
  log_error "fortio pod not found in ${APP_NAMESPACE}. Run: make deploy"
  exit 1
fi
log_ok "fortio client: $FORTIO_POD"

# Verify fortio binary works
if ! kubectl exec -n "${APP_NAMESPACE}" "$FORTIO_POD" -c fortio -- fortio version &>/dev/null; then
  log_error "fortio binary not found in container. Check FORTIO_IMAGE."
  exit 1
fi
FORTIO_VER=$(kubectl exec -n "${APP_NAMESPACE}" "$FORTIO_POD" -c fortio -- fortio version 2>/dev/null || echo "unknown")
log_ok "fortio version: $FORTIO_VER"

AMBIENT_URL="http://http-echo.${APP_NAMESPACE}.svc.cluster.local:80/"
BASELINE_URL="http://http-echo.${APP_NAMESPACE_BASELINE}.svc.cluster.local:80/"

# Verify connectivity before starting
log_info "Verifying connectivity to targets..."
if ! kubectl exec -n "${APP_NAMESPACE}" "$FORTIO_POD" -c fortio -- fortio curl "$AMBIENT_URL" &>/dev/null; then
  log_error "Cannot reach $AMBIENT_URL from fortio pod"
  exit 1
fi
log_ok "Connectivity OK"

# --- Run a single fortio benchmark and print results ---
run_and_report() {
  local label="$1" url="$2" conc="$3"
  shift 3
  local extra_args=("$@")

  # Build fortio command as a single string to run via sh -c inside the container
  local cmd="fortio load -c $conc -qps 0"
  if [[ "$REQUESTS" -gt 0 ]]; then
    cmd+=" -n $REQUESTS"
  else
    cmd+=" -t $DURATION"
  fi
  for arg in "${extra_args[@]}"; do
    cmd+=" $arg"
  done
  cmd+=" '$url' > /tmp/fortio-out.txt 2>&1"

  # Run fortio inside the container, saving output to a file
  kubectl exec -n "${APP_NAMESPACE}" "$FORTIO_POD" -c fortio -- sh -c "$cmd" || true

  # Read the output file from the container
  local raw_output
  raw_output=$(kubectl exec -n "${APP_NAMESPACE}" "$FORTIO_POD" -c fortio -- cat /tmp/fortio-out.txt 2>/dev/null) || true

  if [[ -z "$raw_output" ]] || ! echo "$raw_output" | grep -q "target"; then
    # Show first few lines of error for debugging
    local err_preview
    err_preview=$(echo "$raw_output" | head -5)
    printf "  %-30s  %10s  %s\n" "$label" "FAILED" "${err_preview:0:80}"
    return
  fi

  # Parse fortio text output using grep
  # Fortio output format:
  #   Sockets used: 4
  #   ...
  #   # target 50% 0.000123
  #   # target 75% 0.000234
  #   # target 90% 0.000345
  #   # target 99% 0.000456
  #   # target 99.9% 0.000567
  #   ...
  #   Jitter: false
  #   Code 200 : 12345 (100.0 %)
  #   ...
  #   All done 12345 calls (plus 4 warmup) 0.123 avg, 9876.5 qps
  local qps avg p50 p90 p99 p999 ok_pct

  # QPS from "All done ... qps" line
  qps=$(echo "$raw_output" | grep "All done" | grep -oE '[0-9]+\.[0-9]+ qps' | grep -oE '[0-9]+\.[0-9]+' || echo "N/A")

  # Avg latency from "All done ... avg" line (in seconds)
  avg=$(echo "$raw_output" | grep "All done" | grep -oE '[0-9]+\.[0-9]+ avg' | grep -oE '[0-9]+\.[0-9]+' || echo "N/A")

  # Percentiles from "# target NN% VALUE" lines
  p50=$(echo "$raw_output" | grep "target 50%" | awk '{print $NF}' || echo "N/A")
  p90=$(echo "$raw_output" | grep "target 90%" | awk '{print $NF}' || echo "N/A")
  p99=$(echo "$raw_output" | grep "target 99%" | grep -v "99.9" | awk '{print $NF}' || echo "N/A")
  p999=$(echo "$raw_output" | grep "target 99.9%" | awk '{print $NF}' || echo "N/A")

  # Success rate from "Code 200 : NNNN (NN.N %)" line
  ok_pct=$(echo "$raw_output" | grep "Code 200" | grep -oE '[0-9]+\.[0-9]+ %' | head -1 || echo "")

  # Convert seconds to milliseconds
  to_ms() {
    local val="$1"
    [[ -z "$val" || "$val" == "N/A" ]] && echo "N/A" && return
    awk "BEGIN {printf \"%.3f\", $val * 1000}" 2>/dev/null || echo "$val"
  }

  printf "  %-30s  %10s  %8s  %8s  %8s  %8s  %8s  %s\n" \
    "$label" "${qps:-N/A}" "$(to_ms "$avg")ms" "$(to_ms "$p50")ms" "$(to_ms "$p90")ms" "$(to_ms "$p99")ms" "$(to_ms "$p999")ms" "${ok_pct:+${ok_pct}ok}"
}

# --- Header for table ---
print_table_header() {
  printf "  %-30s  %10s  %8s  %8s  %8s  %8s  %8s  %s\n" \
    "Test" "QPS" "Avg" "P50" "P90" "P99" "P99.9" "Status"
  printf "  %-30s  %10s  %8s  %8s  %8s  %8s  %8s  %s\n" \
    "------------------------------" "----------" "--------" "--------" "--------" "--------" "--------" "------"
}

# === Benchmark: Throughput & Latency by Payload Size ===
# Uses HTTP POST with varying body sizes to measure how ztunnel handles
# different payload sizes. Reports QPS and latency percentiles per size.
bench_by_payload_size() {
  local mode_name="$1" url="$2"

  echo ""
  echo "=================================================================="
  echo "  Throughput & Latency by Payload Size - POST ($mode_name)"
  echo "  URL: $url"
  echo "  Concurrency: $CONCURRENCY, Duration: $DURATION"
  echo "=================================================================="
  echo ""
  print_table_header

  IFS=',' read -ra SIZES <<< "$PACKET_SIZES"
  for size in "${SIZES[@]}"; do
    log_step "BENCH" "[$mode_name-${size}B] POST payload=${size}B, c=$CONCURRENCY..."
    run_and_report "${size}B POST" "$url" "$CONCURRENCY" \
      "-payload-size" "$size" "-content-type" "application/octet-stream"
  done
}

# === Benchmark: HTTP Application-Level ===
bench_http_app() {
  local mode_name="$1" url="$2"

  echo ""
  echo "=================================================================="
  echo "  HTTP Application Benchmark ($mode_name)"
  echo "  URL: $url"
  echo "  Concurrency: $CONCURRENCY, Duration: $DURATION"
  echo "=================================================================="
  echo ""
  print_table_header

  log_step "BENCH" "[$mode_name] HTTP GET (keep-alive)..."
  run_and_report "HTTP GET" "$url" "$CONCURRENCY"

  log_step "BENCH" "[$mode_name] HTTP GET (no keep-alive)..."
  run_and_report "HTTP GET (no keepalive)" "$url" "$CONCURRENCY" "-keepalive=false"

  log_step "BENCH" "[$mode_name] HTTP POST 1KB..."
  run_and_report "HTTP POST 1KB" "$url" "$CONCURRENCY" \
    "-payload-size" "1024" "-content-type" "application/json"

  log_step "BENCH" "[$mode_name] HTTP GET burst (c=32)..."
  run_and_report "HTTP GET (c=32 burst)" "$url" 32
}

# === Benchmark: Concurrency Sweep ===
bench_concurrency_sweep() {
  local mode_name="$1" url="$2"

  echo ""
  echo "=================================================================="
  echo "  Concurrency Sweep ($mode_name)"
  echo "  URL: $url, Duration: $DURATION"
  echo "=================================================================="
  echo ""
  print_table_header

  for conc in 1 2 4 8 16 32 64; do
    log_step "BENCH" "[$mode_name] c=$conc..."
    run_and_report "c=$conc" "$url" "$conc"
  done
}

# === Main ===
log_info "Performance benchmark suite"
log_info "  MODE=$MODE  CONCURRENCY=$CONCURRENCY  DURATION=$DURATION  SIZES=$PACKET_SIZES"
log_info "  Report: $REPORT_FILE"
echo ""

{
  echo "ztunnel-testbed Performance Report"
  echo "Generated: $(date)"
  echo "Cluster: $(kubectl config current-context 2>/dev/null || echo unknown)"
  echo "Nodes: $(kubectl get nodes --no-headers 2>/dev/null | wc -l | tr -d ' ')"
  echo "fortio: $FORTIO_VER"
  echo "Mode: $MODE  Concurrency: $CONCURRENCY  Duration: $DURATION  Sizes: $PACKET_SIZES"
  echo ""

  run_mode() {
    local mode_name="$1" url="$2"
    bench_by_payload_size "$mode_name" "$url"
    bench_http_app "$mode_name" "$url"
    if [[ "$SKIP_SWEEP" != "1" ]]; then
      bench_concurrency_sweep "$mode_name" "$url"
    fi
  }

  suite_start=$(date +%s)

  if [[ "$MODE" == "ambient" ]]; then
    run_mode "ambient" "$AMBIENT_URL"
  elif [[ "$MODE" == "baseline" ]]; then
    run_mode "baseline" "$BASELINE_URL"
  else
    run_mode "ambient" "$AMBIENT_URL"
    run_mode "baseline" "$BASELINE_URL"

    echo ""
    echo "=================================================================="
    echo "  Summary: Ambient vs Baseline"
    echo "=================================================================="
    echo ""
    echo "  Compare QPS and P99 columns between ambient and baseline."
    echo "  Ambient adds mTLS (ztunnel HBONE) overhead; typical impact:"
    echo "    - Latency: +0.1-0.5ms P99 (mTLS handshake amortized over keep-alive)"
    echo "    - Throughput: -5-15% (encryption overhead, varies by payload size)"
    echo ""
  fi

  suite_elapsed=$(( $(date +%s) - suite_start ))
  echo ""
  echo "Benchmark completed in ${suite_elapsed}s"

} 2>&1 | tee "$REPORT_FILE"

log_ok "Report saved to: $REPORT_FILE"
