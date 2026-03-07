#!/usr/bin/env bash
# =============================================================================
# ztunnel-testbed - Performance benchmark suite
# =============================================================================
# Comprehensive throughput and latency benchmarks for ztunnel ambient mode.
#
# Test matrix:
#   1. Throughput by payload size (64, 128, 256, 512, 1024, 1500 bytes)
#   2. P99 latency by payload size (single-trip and round-trip)
#   3. HTTP application-level benchmark (GET/POST, keep-alive, concurrency sweep)
#   4. Ambient vs baseline comparison for all tests
#
# Uses fortio for all load generation (precise histograms, JSON output).
#
# Params (env vars):
#   MODE          - ambient | baseline | both (default: both)
#   CONCURRENCY   - concurrent connections (default: 4)
#   DURATION      - per-test duration (default: 15s)
#   REQUESTS      - total requests per test (default: 0 = use DURATION)
#   PACKET_SIZES  - comma-separated payload sizes (default: 64,128,256,512,1024,1500)
#   OUTPUT_DIR    - results directory (default: .bench-results)
#   SKIP_SWEEP    - set to 1 to skip concurrency sweep (default: 0)
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
source "${PROJECT_ROOT}/scripts/common.sh"

# Defaults
MODE="${MODE:-both}"
CONCURRENCY="${CONCURRENCY:-4}"
DURATION="${DURATION:-15s}"
REQUESTS="${REQUESTS:-0}"
PACKET_SIZES="${PACKET_SIZES:-64,128,256,512,1024,1500}"
OUTPUT_DIR="${OUTPUT_DIR:-${PROJECT_ROOT}/.bench-results}"
SKIP_SWEEP="${SKIP_SWEEP:-0}"

mkdir -p "$OUTPUT_DIR"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
REPORT_FILE="${OUTPUT_DIR}/report-${TIMESTAMP}.txt"

ensure_kubectl_context

# --- Discover client pods ---
FORTIO_POD=$(kubectl get pods -n "${APP_NAMESPACE}" -l app=fortio -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
if [[ -z "$FORTIO_POD" ]]; then
  log_error "fortio pod not found in ${APP_NAMESPACE}. Run: make deploy"
  exit 1
fi
log_ok "fortio client: $FORTIO_POD"

# Target URLs
AMBIENT_URL="http://http-echo.${APP_NAMESPACE}.svc.cluster.local:80/"
BASELINE_URL="http://http-echo.${APP_NAMESPACE_BASELINE}.svc.cluster.local:80/"

# --- Helper: run a single fortio benchmark ---
# Args: $1=label, $2=url, $3=concurrency, $4=extra_args...
# Outputs: JSON result path
run_fortio() {
  local label="$1" url="$2" conc="$3"
  shift 3
  local extra_args=("$@")
  local json_file="/tmp/bench-${label}.json"

  local load_args=(-c "$conc" -qps 0 -json "$json_file" -a)
  if [[ "$REQUESTS" -gt 0 ]]; then
    load_args+=(-n "$REQUESTS")
  else
    load_args+=(-t "$DURATION")
  fi
  load_args+=("${extra_args[@]}")
  load_args+=("$url")

  kubectl exec -n "${APP_NAMESPACE}" "$FORTIO_POD" -c fortio -- \
    fortio load "${load_args[@]}" >/dev/null 2>&1 || true

  echo "$json_file"
}

# --- Helper: extract metrics from fortio JSON ---
extract_metrics() {
  local json_file="$1" label="$2"
  local out
  out=$(kubectl exec -n "${APP_NAMESPACE}" "$FORTIO_POD" -c fortio -- cat "$json_file" 2>/dev/null || true)
  if [[ -z "$out" ]]; then
    echo "  $label: [no data]"
    return
  fi

  local avg_latency p50 p90 p99 p999 qps throughput_bps
  avg_latency=$(echo "$out" | python3 -c "import sys,json; d=json.load(sys.stdin); print(f\"{d['DurationHistogram']['Avg']*1000:.3f}\")" 2>/dev/null || echo "N/A")
  p50=$(echo "$out" | python3 -c "import sys,json; d=json.load(sys.stdin); ps=d['DurationHistogram']['Percentiles']; print(f\"{next((p['Value']*1000 for p in ps if p['Percentile']==50),0):.3f}\")" 2>/dev/null || echo "N/A")
  p90=$(echo "$out" | python3 -c "import sys,json; d=json.load(sys.stdin); ps=d['DurationHistogram']['Percentiles']; print(f\"{next((p['Value']*1000 for p in ps if p['Percentile']==90),0):.3f}\")" 2>/dev/null || echo "N/A")
  p99=$(echo "$out" | python3 -c "import sys,json; d=json.load(sys.stdin); ps=d['DurationHistogram']['Percentiles']; print(f\"{next((p['Value']*1000 for p in ps if p['Percentile']==99),0):.3f}\")" 2>/dev/null || echo "N/A")
  p999=$(echo "$out" | python3 -c "import sys,json; d=json.load(sys.stdin); ps=d['DurationHistogram']['Percentiles']; print(f\"{next((p['Value']*1000 for p in ps if p['Percentile']==99.9),0):.3f}\")" 2>/dev/null || echo "N/A")
  qps=$(echo "$out" | python3 -c "import sys,json; d=json.load(sys.stdin); print(f\"{d['ActualQPS']:.1f}\")" 2>/dev/null || echo "N/A")
  throughput_bps=$(echo "$out" | python3 -c "import sys,json; d=json.load(sys.stdin); sz=d.get('Sizes',{}).get('Avg',0); print(f\"{d['ActualQPS']*sz*8/1e6:.2f}\")" 2>/dev/null || echo "N/A")

  printf "  %-35s QPS: %8s  Avg: %7sms  P50: %7sms  P90: %7sms  P99: %7sms  P99.9: %7sms  Tput: %sMbps\n" \
    "$label" "$qps" "$avg_latency" "$p50" "$p90" "$p99" "$p999" "$throughput_bps"
}

# --- Benchmark: Throughput & Latency by Payload Size ---
bench_by_payload_size() {
  local mode_name="$1" url="$2"

  echo ""
  echo "=================================================================="
  echo "  Throughput & Latency by Payload Size ($mode_name)"
  echo "  URL: $url"
  echo "  Concurrency: $CONCURRENCY, Duration: $DURATION"
  echo "=================================================================="
  echo ""
  printf "  %-35s %8s  %9s  %9s  %9s  %9s  %9s  %s\n" \
    "Test" "QPS" "Avg" "P50" "P90" "P99" "P99.9" "Throughput"

  IFS=',' read -ra SIZES <<< "$PACKET_SIZES"
  for size in "${SIZES[@]}"; do
    local payload
    payload=$(python3 -c "print('x'*${size})" 2>/dev/null || printf '%0.sx' $(seq 1 "$size"))
    local label="${mode_name}-${size}B"

    log_step "BENCH" "[$label] payload=${size}B, concurrency=$CONCURRENCY..."
    local json_file
    json_file=$(run_fortio "$label" "$url" "$CONCURRENCY" \
      -payload "$payload" \
      -content-type "application/octet-stream")
    extract_metrics "$json_file" "${size}B payload"
  done
}

# --- Benchmark: HTTP Application-Level ---
bench_http_app() {
  local mode_name="$1" url="$2"

  echo ""
  echo "=================================================================="
  echo "  HTTP Application Benchmark ($mode_name)"
  echo "  URL: $url"
  echo "  Concurrency: $CONCURRENCY, Duration: $DURATION"
  echo "=================================================================="
  echo ""
  printf "  %-35s %8s  %9s  %9s  %9s  %9s  %9s  %s\n" \
    "Test" "QPS" "Avg" "P50" "P90" "P99" "P99.9" "Throughput"

  # GET request (default)
  log_step "BENCH" "[${mode_name}-http-get] HTTP GET..."
  json_file=$(run_fortio "${mode_name}-http-get" "$url" "$CONCURRENCY")
  extract_metrics "$json_file" "HTTP GET"

  # GET with keep-alive disabled
  log_step "BENCH" "[${mode_name}-http-no-keepalive] HTTP GET (no keep-alive)..."
  json_file=$(run_fortio "${mode_name}-http-no-keepalive" "$url" "$CONCURRENCY" -keepalive=false)
  extract_metrics "$json_file" "HTTP GET (no keep-alive)"

  # POST with 1KB body
  local post_payload
  post_payload=$(python3 -c "print('P'*1024)" 2>/dev/null || printf '%0.sP' $(seq 1 1024))
  log_step "BENCH" "[${mode_name}-http-post-1k] HTTP POST 1KB..."
  json_file=$(run_fortio "${mode_name}-http-post-1k" "$url" "$CONCURRENCY" \
    -payload "$post_payload" -content-type "application/json")
  extract_metrics "$json_file" "HTTP POST 1KB"

  # High concurrency burst
  log_step "BENCH" "[${mode_name}-http-burst] HTTP GET (concurrency=32)..."
  json_file=$(run_fortio "${mode_name}-http-burst" "$url" 32)
  extract_metrics "$json_file" "HTTP GET (c=32 burst)"
}

# --- Benchmark: Concurrency Sweep ---
bench_concurrency_sweep() {
  local mode_name="$1" url="$2"

  echo ""
  echo "=================================================================="
  echo "  Concurrency Sweep ($mode_name)"
  echo "  URL: $url, Duration: $DURATION"
  echo "=================================================================="
  echo ""
  printf "  %-35s %8s  %9s  %9s  %9s  %9s  %9s  %s\n" \
    "Test" "QPS" "Avg" "P50" "P90" "P99" "P99.9" "Throughput"

  for conc in 1 2 4 8 16 32 64; do
    log_step "BENCH" "[${mode_name}-c${conc}] concurrency=$conc..."
    json_file=$(run_fortio "${mode_name}-c${conc}" "$url" "$conc")
    extract_metrics "$json_file" "c=$conc"
  done
}

# --- Main execution ---
log_info "Performance benchmark suite"
log_info "  MODE=$MODE  CONCURRENCY=$CONCURRENCY  DURATION=$DURATION  SIZES=$PACKET_SIZES"
log_info "  Report: $REPORT_FILE"
echo ""

{
  echo "ztunnel-testbed Performance Report"
  echo "Generated: $(date)"
  echo "Cluster: $(kubectl config current-context 2>/dev/null || echo unknown)"
  echo "Nodes: $(kubectl get nodes --no-headers 2>/dev/null | wc -l | tr -d ' ')"
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
    echo "  Summary: Ambient vs Baseline Comparison"
    echo "=================================================================="
    echo ""
    echo "  Compare the QPS and P99 columns above between ambient and baseline."
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
