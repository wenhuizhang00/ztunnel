#!/usr/bin/env bash
# =============================================================================
# Latency benchmark
# =============================================================================
# Measures Min/Avg/Max/AvgPct latency in microseconds for varying payload
# sizes, connection types, and concurrency levels.
# Outputs a single summary table at the end.
#
# Single-node:  fortio-client → ztunnel (local) → fortio-server
# Multi-node:   fortio-client (node1) → ztunnel HBONE → fortio-server (node2)
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
source "${PROJECT_ROOT}/scripts/common.sh"
source "${PROJECT_ROOT}/tests/performance/bench-common.sh"

TOPOLOGY="${TOPOLOGY:-local}"
BENCH_TYPE="latency"

[[ "${CONCURRENCY}" == "4" ]] && CONCURRENCY=1

log_info "Latency benchmark (topology=$TOPOLOGY, mode=$MODE, c=$CONCURRENCY)"

# Accumulate rows for final summary table
_LAT_ROWS=""
add_row() {
  _LAT_ROWS+="$1"$'\n'
}

# Run a single fortio test and capture the result as a table row
run_lat_row() {
  local label="$1" ns="$2" client_pod="$3" url="$4" conc="$5"
  shift 5

  local -a load_args=(fortio load -c "$conc" -qps 0)
  if [[ "$REQUESTS" -gt 0 ]]; then
    load_args+=(-n "$REQUESTS")
  else
    load_args+=(-t "$DURATION")
  fi
  for arg in "$@"; do
    load_args+=($arg)
  done
  load_args+=("$url")

  local raw
  raw=$(kubectl exec -n "$ns" "$client_pod" -c fortio -- "${load_args[@]}" 2>&1) || true

  if [[ -z "$raw" ]] || ! echo "$raw" | grep -q "All done"; then
    add_row "$(printf "  %-32s  %8s  %8s  %8s  %10s  %s" "$label" "ERR" "ERR" "ERR" "ERR" "")"
    return
  fi

  local avg p50 p90 p99 p999 lat_min lat_max ok_pct

  avg=$(echo "$raw" | grep "Aggregated Function" | grep -oE 'avg [0-9.e+-]+' | grep -oE '[0-9.e+-]+' || echo "N/A")
  lat_min=$(echo "$raw" | grep "Aggregated Function" | grep -oE 'min [0-9.e+-]+' | grep -oE '[0-9.e+-]+' || echo "N/A")
  lat_max=$(echo "$raw" | grep "Aggregated Function" | grep -oE 'max [0-9.e+-]+' | grep -oE '[0-9.e+-]+' || echo "N/A")

  get_pct() {
    local pct="$1"
    echo "$raw" | grep "# target ${pct}" | head -1 | awk '{print $NF}' || true
  }
  p50=$(get_pct "50%"); [[ -n "$p50" ]] || p50="N/A"
  p90=$(get_pct "90%"); [[ -n "$p90" ]] || p90="N/A"
  p99=$(echo "$raw" | grep "# target 99%" | grep -v "99.9" | head -1 | awk '{print $NF}' || true); [[ -n "$p99" ]] || p99="N/A"
  p999=$(get_pct "99.9%"); [[ -n "$p999" ]] || p999="N/A"
  ok_pct=$(echo "$raw" | grep "Code 200" | grep -oE '[0-9]+\.[0-9]+ %' | head -1 || echo "")

  to_us() {
    local v="$1"
    [[ -z "$v" || "$v" == "N/A" ]] && echo "N/A" && return
    awk "BEGIN {printf \"%.1f\", $v * 1000000}" 2>/dev/null || echo "$v"
  }

  local avg_pct_us="N/A"
  if [[ "$p50" != "N/A" ]] && [[ "$p90" != "N/A" ]] && [[ "$p99" != "N/A" ]] && [[ "$p999" != "N/A" ]]; then
    avg_pct_us=$(awk "BEGIN {printf \"%.1f\", ($p50 + $p90 + $p99 + $p999) / 4.0 * 1000000}" 2>/dev/null || echo "N/A")
  fi

  add_row "$(printf "  %-32s  %8s  %8s  %8s  %10s  %s" \
    "$label" "$(to_us "$lat_min")" "$(to_us "$avg")" "$(to_us "$lat_max")" "$avg_pct_us" "$ok_pct")"
}

# Run all latency tests for a mode
run_all_latency() {
  local mode="$1" ns="$2" client="$3" url="$4" topo_label="$5"

  add_row ""
  add_row "  --- $mode ($topo_label) ---"

  # Payload sizes
  IFS=',' read -ra SIZES <<< "$PACKET_SIZES"
  for size in "${SIZES[@]}"; do
    log_step "LAT" "[$mode/$topo_label ${size}B] c=$CONCURRENCY..." >&2
    run_lat_row "${mode}/${topo_label} ${size}B POST" "$ns" "$client" "$url" "$CONCURRENCY" \
      -payload-size "$size" -content-type "application/octet-stream"
  done

  # HTTP methods
  log_step "LAT" "[$mode/$topo_label] GET c=1..." >&2
  run_lat_row "${mode}/${topo_label} GET c=1" "$ns" "$client" "$url" 1

  log_step "LAT" "[$mode/$topo_label] GET no-keepalive c=1..." >&2
  run_lat_row "${mode}/${topo_label} GET no-ka c=1" "$ns" "$client" "$url" 1 -keepalive=false

  log_step "LAT" "[$mode/$topo_label] POST 1KB c=1..." >&2
  run_lat_row "${mode}/${topo_label} POST 1KB c=1" "$ns" "$client" "$url" 1 \
    -payload-size 1024 -content-type "application/json"

  # Concurrency impact
  for conc in 4 16 64; do
    log_step "LAT" "[$mode/$topo_label] GET c=$conc..." >&2
    run_lat_row "${mode}/${topo_label} GET c=$conc" "$ns" "$client" "$url" "$conc"
  done
}

{
  print_report_header "LATENCY" "$TOPOLOGY"

  suite_start=$(date +%s)

  if [[ "$TOPOLOGY" == "cross-node" ]]; then
    resolve_cross_node_pods
    collect_ztunnel_stats "before latency"

    [[ "$MODE" != "baseline" ]] && \
      run_all_latency "ambient" "$APP_NAMESPACE" "$CROSS_CLIENT" "$CROSS_URL_REMOTE" "cross-node"
    run_all_latency "same-node" "$APP_NAMESPACE" "$CROSS_CLIENT" "$CROSS_URL_LOCAL" "same-node"

    collect_ztunnel_stats "after latency"
  else
    collect_ztunnel_stats "before latency"

    [[ "$MODE" != "baseline" ]] && [[ -n "$AMBIENT_CLIENT" ]] && \
      run_all_latency "ambient" "$APP_NAMESPACE" "$AMBIENT_CLIENT" "$AMBIENT_URL" "single-node"
    [[ "$MODE" != "ambient" ]] && [[ -n "$BASELINE_CLIENT" ]] && \
      run_all_latency "baseline" "$APP_NAMESPACE_BASELINE" "$BASELINE_CLIENT" "$BASELINE_URL" "single-node"

    collect_ztunnel_stats "after latency"
  fi

  suite_elapsed=$(( $(date +%s) - suite_start ))

  # Print single summary table
  echo ""
  echo "=================================================================="
  echo "  LATENCY SUMMARY (all tests, microseconds)"
  echo "  Lower = better. AvgPct = mean of P50/P90/P99/P99.9."
  echo "  Duration: $DURATION per test"
  echo "=================================================================="
  echo ""
  printf "  %-32s  %8s  %8s  %8s  %10s  %s\n" \
    "Test" "Min(us)" "Avg(us)" "Max(us)" "AvgPct(us)" "OK%"
  printf "  %-32s  %8s  %8s  %8s  %10s  %s\n" \
    "--------------------------------" "--------" "--------" "--------" "----------" "------"
  echo "$_LAT_ROWS"
  echo ""
  echo "Latency benchmark completed in ${suite_elapsed}s"

} 2>&1 | tee "$REPORT_FILE"

log_ok "Report: $REPORT_FILE"
