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

  local load_args=(-c "$conc" -qps 0)
  if [[ "$REQUESTS" -gt 0 ]]; then
    load_args+=(-n "$REQUESTS")
  else
    load_args+=(-t "$DURATION")
  fi
  load_args+=("${extra_args[@]}")
  load_args+=("$url")

  # Run fortio and capture text output (includes percentiles)
  local raw_output
  raw_output=$(kubectl exec -n "${APP_NAMESPACE}" "$FORTIO_POD" -c fortio -- \
    fortio load "${load_args[@]}" 2>&1) || true

  if [[ -z "$raw_output" ]]; then
    printf "  %-30s  %10s  %8s  %8s  %8s  %8s  %8s\n" "$label" "FAILED" "-" "-" "-" "-" "-"
    return
  fi

  # Parse fortio text output
  local qps avg p50 p90 p99 p999 ok_pct
  qps=$(echo "$raw_output" | grep -oP 'Aggregated Function.*qps=\K[0-9.]+' || echo "$raw_output" | grep 'target.*qps' | grep -oP '[0-9.]+' | tail -1 || echo "N/A")
  [[ -z "$qps" ]] && qps=$(echo "$raw_output" | grep -i 'qps' | head -1 | grep -oP '[0-9]+\.[0-9]+' | head -1 || echo "N/A")

  avg=$(echo "$raw_output" | grep -oP 'avg\s+\K[0-9.]+' | head -1 || echo "N/A")
  p50=$(echo "$raw_output" | grep -P '^\# target 50%' | grep -oP '[0-9.]+$' || echo "$raw_output" | grep '50%' | grep -oP '[0-9.]+' | tail -1 || echo "N/A")
  p90=$(echo "$raw_output" | grep -P '^\# target 90%' | grep -oP '[0-9.]+$' || echo "$raw_output" | grep '90%' | grep -oP '[0-9.]+' | tail -1 || echo "N/A")
  p99=$(echo "$raw_output" | grep -P '^\# target 99%' | grep -oP '[0-9.]+$' || echo "$raw_output" | grep '99%' | grep -oP '[0-9.]+' | tail -1 || echo "N/A")
  p999=$(echo "$raw_output" | grep -P '^\# target 99\.9%' | grep -oP '[0-9.]+$' || echo "$raw_output" | grep '99.9%' | grep -oP '[0-9.]+' | tail -1 || echo "N/A")

  # Convert seconds to milliseconds for latency
  to_ms() {
    local val="$1"
    [[ "$val" == "N/A" ]] && echo "N/A" && return
    awk "BEGIN {printf \"%.3f\", $val * 1000}" 2>/dev/null || echo "$val"
  }

  local avg_ms p50_ms p90_ms p99_ms p999_ms
  avg_ms=$(to_ms "$avg")
  p50_ms=$(to_ms "$p50")
  p90_ms=$(to_ms "$p90")
  p99_ms=$(to_ms "$p99")
  p999_ms=$(to_ms "$p999")

  # HTTP success rate
  ok_pct=$(echo "$raw_output" | grep -oP 'All done.*success\s+\K[0-9.]+' || echo "$raw_output" | grep 'Code 200' | grep -oP '[0-9.]+%' | head -1 || echo "")

  printf "  %-30s  %10s  %8s  %8s  %8s  %8s  %8s  %s\n" \
    "$label" "${qps:-N/A}" "${avg_ms}ms" "${p50_ms}ms" "${p90_ms}ms" "${p99_ms}ms" "${p999_ms}ms" "${ok_pct:+${ok_pct}% ok}"
}

# --- Header for table ---
print_table_header() {
  printf "  %-30s  %10s  %8s  %8s  %8s  %8s  %8s  %s\n" \
    "Test" "QPS" "Avg" "P50" "P90" "P99" "P99.9" "Status"
  printf "  %-30s  %10s  %8s  %8s  %8s  %8s  %8s  %s\n" \
    "------------------------------" "----------" "--------" "--------" "--------" "--------" "--------" "------"
}

# === Benchmark: Throughput & Latency by Payload Size ===
bench_by_payload_size() {
  local mode_name="$1" url="$2"

  echo ""
  echo "=================================================================="
  echo "  Throughput & Latency by Payload Size ($mode_name)"
  echo "  URL: $url"
  echo "  Concurrency: $CONCURRENCY, Duration: $DURATION"
  echo "=================================================================="
  echo ""
  print_table_header

  IFS=',' read -ra SIZES <<< "$PACKET_SIZES"
  for size in "${SIZES[@]}"; do
    log_step "BENCH" "[$mode_name-${size}B] payload=${size}B, c=$CONCURRENCY..."
    run_and_report "${size}B payload" "$url" "$CONCURRENCY" -payload-size "$size"
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
  run_and_report "HTTP GET (no keepalive)" "$url" "$CONCURRENCY" -keepalive=false

  log_step "BENCH" "[$mode_name] HTTP POST 1KB..."
  run_and_report "HTTP POST 1KB" "$url" "$CONCURRENCY" -payload-size 1024 -content-type "application/json"

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
