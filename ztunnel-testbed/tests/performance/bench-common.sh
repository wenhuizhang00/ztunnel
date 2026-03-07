#!/usr/bin/env bash
# =============================================================================
# Performance benchmark shared functions
# =============================================================================
# Sourced by bench-throughput.sh, bench-latency.sh, and run-bench.sh
# =============================================================================

MODE="${MODE:-both}"
CONCURRENCY="${CONCURRENCY:-4}"
DURATION="${DURATION:-20s}"
REQUESTS="${REQUESTS:-0}"
PACKET_SIZES="${PACKET_SIZES:-64,128,256,512,1024,1500}"
OUTPUT_DIR="${OUTPUT_DIR:-${PROJECT_ROOT}/.bench-results}"
SKIP_SWEEP="${SKIP_SWEEP:-0}"

mkdir -p "$OUTPUT_DIR"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
REPORT_FILE="${OUTPUT_DIR}/${BENCH_TYPE:-bench}-${TOPOLOGY:-local}-${TIMESTAMP}.txt"

ensure_kubectl_context

# --- Discover pods ---
find_pod() {
  local ns="$1" label="$2"
  kubectl get pods -n "$ns" -l "$label" --field-selector=status.phase=Running \
    -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true
}

AMBIENT_CLIENT=$(find_pod "$APP_NAMESPACE" "app=fortio-client")
BASELINE_CLIENT=$(find_pod "$APP_NAMESPACE_BASELINE" "app=fortio-client")
AMBIENT_URL="http://fortio-server.${APP_NAMESPACE}.svc.cluster.local:8080/"
BASELINE_URL="http://fortio-server.${APP_NAMESPACE_BASELINE}.svc.cluster.local:8080/"

# Cross-node pod discovery (set by resolve_cross_node_pods)
CROSS_CLIENT=""
CROSS_URL_REMOTE=""
CROSS_URL_LOCAL=""

resolve_cross_node_pods() {
  CROSS_CLIENT=$(find_pod "$APP_NAMESPACE" "app=fortio-client-node1")
  if [[ -z "$CROSS_CLIENT" ]]; then
    # Fall back to regular client
    CROSS_CLIENT=$(find_pod "$APP_NAMESPACE" "app=fortio-client")
  fi
  CROSS_URL_REMOTE="http://fortio-server-node2.${APP_NAMESPACE}.svc.cluster.local:8080/"
  CROSS_URL_LOCAL="http://fortio-server-node1.${APP_NAMESPACE}.svc.cluster.local:8080/"

  if [[ -z "$CROSS_CLIENT" ]]; then
    log_error "No fortio-client found for cross-node tests. Run: make deploy"
    exit 1
  fi

  # Verify cross-node services exist
  local remote_ok local_ok
  remote_ok=$(kubectl get svc fortio-server-node2 -n "$APP_NAMESPACE" -o name 2>/dev/null || true)
  local_ok=$(kubectl get svc fortio-server-node1 -n "$APP_NAMESPACE" -o name 2>/dev/null || true)
  if [[ -z "$remote_ok" ]] || [[ -z "$local_ok" ]]; then
    log_error "Cross-node fortio services not found. Redeploy with multi-node: WORKER_NODES=<ip> make create-baremetal && make deploy"
    exit 1
  fi

  local client_node
  client_node=$(kubectl get pod "$CROSS_CLIENT" -n "$APP_NAMESPACE" -o jsonpath='{.spec.nodeName}' 2>/dev/null || true)
  log_ok "Cross-node: client=$CROSS_CLIENT on $client_node"
}

# Verify fortio binary
verify_clients() {
  local verified=0
  if [[ -n "$AMBIENT_CLIENT" ]] && [[ "$MODE" != "baseline" ]]; then
    kubectl exec -n "$APP_NAMESPACE" "$AMBIENT_CLIENT" -c fortio -- fortio version &>/dev/null || {
      log_error "fortio not working in $AMBIENT_CLIENT"; exit 1; }
    kubectl exec -n "$APP_NAMESPACE" "$AMBIENT_CLIENT" -c fortio -- fortio curl "$AMBIENT_URL" &>/dev/null || {
      log_error "Cannot reach $AMBIENT_URL"; exit 1; }
    ((verified++)) || true
  fi
  if [[ -n "$BASELINE_CLIENT" ]] && [[ "$MODE" != "ambient" ]]; then
    kubectl exec -n "$APP_NAMESPACE_BASELINE" "$BASELINE_CLIENT" -c fortio -- fortio version &>/dev/null || {
      log_error "fortio not working in $BASELINE_CLIENT"; exit 1; }
    kubectl exec -n "$APP_NAMESPACE_BASELINE" "$BASELINE_CLIENT" -c fortio -- fortio curl "$BASELINE_URL" &>/dev/null || {
      log_error "Cannot reach $BASELINE_URL"; exit 1; }
    ((verified++)) || true
  fi
  [[ "$verified" -gt 0 ]] || { log_error "No fortio clients available. Run: make deploy"; exit 1; }
  log_ok "fortio clients verified ($verified)"
}

verify_clients

# --- Run fortio and parse results ---
run_and_report() {
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
    local err_msg
    err_msg=$(echo "$raw" | tail -3 | tr '\n' ' ')
    printf "  %-28s  %10s  %9s  %9s  %9s  %9s  %9s  %s\n" "$label" "ERROR" "-" "-" "-" "-" "-" "${err_msg:0:50}"
    return
  fi


  local qps avg p50 p90 p99 p999 ok_pct

  # QPS from "All done ... YYYY.Y qps"
  qps=$(echo "$raw" | grep "All done" | grep -oE '[0-9]+\.[0-9]+ qps' | grep -oE '[0-9]+\.[0-9]+' || echo "N/A")

  # Average latency from "Aggregated Function : count NNN avg X.XXXXXX"
  # (more reliable than "All done" line which may use different units)
  avg=$(echo "$raw" | grep "Aggregated Function" | grep -oE 'avg [0-9.e+-]+' | grep -oE '[0-9.e+-]+' || echo "N/A")

  # Percentiles from "# target NN% X.XXXXXXX" lines
  # Extract the last space-separated field (the latency value in seconds)
  get_pct() {
    local pct="$1"
    local val
    val=$(echo "$raw" | grep "# target ${pct}" | head -1 | awk '{print $NF}' || true)
    [[ -n "$val" ]] && echo "$val" || echo "N/A"
  }
  p50=$(get_pct "50%")
  p90=$(get_pct "90%")
  p99=$(echo "$raw" | grep "# target 99%" | grep -v "99.9" | head -1 | awk '{print $NF}' || true)
  [[ -n "$p99" ]] || p99="N/A"
  p999=$(get_pct "99.9%")

  # Min/max from "Aggregated Function Time : ... min X.XXX max X.XXX"
  local lat_min lat_max
  lat_min=$(echo "$raw" | grep "Aggregated Function" | grep -oE 'min [0-9.e+-]+' | grep -oE '[0-9.e+-]+' || echo "N/A")
  lat_max=$(echo "$raw" | grep "Aggregated Function" | grep -oE 'max [0-9.e+-]+' | grep -oE '[0-9.e+-]+' || echo "N/A")

  # Success rate from "Code 200 : NNNNN (NN.N %)"
  ok_pct=$(echo "$raw" | grep "Code 200" | grep -oE '[0-9]+\.[0-9]+ %' | head -1 || echo "")

  to_us() {
    local v="$1"
    [[ -z "$v" || "$v" == "N/A" ]] && echo "N/A" && return
    awk "BEGIN {printf \"%.1f\", $v * 1000000}" 2>/dev/null || echo "$v"
  }

  # Mean of P99 latency in microseconds
  local avg_pct_us="N/A"
  if [[ "$p99" != "N/A" ]]; then
    avg_pct_us=$(awk "BEGIN {printf \"%.1f\", $p99 * 1000000}" 2>/dev/null || echo "N/A")
  fi

  # Extract payload size from label (e.g. "64B POST" -> 64)
  local payload_bytes
  payload_bytes=$(echo "$label" | grep -oE '^[0-9]+' || echo "0")

  # Compute throughput in Mbps and Kpps
  local mbps="N/A" kpps="N/A"
  if [[ "$qps" != "N/A" ]] && [[ "$payload_bytes" -gt 0 ]]; then
    mbps=$(awk "BEGIN {printf \"%.2f\", $qps * $payload_bytes * 8 / 1000000}" 2>/dev/null || echo "N/A")
    kpps=$(awk "BEGIN {printf \"%.1f\", $qps / 1000}" 2>/dev/null || echo "N/A")
  elif [[ "$qps" != "N/A" ]]; then
    kpps=$(awk "BEGIN {printf \"%.1f\", $qps / 1000}" 2>/dev/null || echo "N/A")
  fi

  # Output format depends on BENCH_TYPE
  case "${BENCH_TYPE:-all}" in
    throughput)
      printf "  %-22s  %10s  %8s  %10s  %s\n" \
        "$label" "${qps:-N/A}" "${kpps}" "${mbps}" "${ok_pct}"
      ;;
    latency)
      printf "  %-22s  %8s  %8s  %8s  %10s  %s\n" \
        "$label" "$(to_us "$lat_min")" "$(to_us "$avg")" "$(to_us "$lat_max")" "${avg_pct_us}" "${ok_pct}"
      ;;
    *)
      printf "  %-22s  %10s  %8s  %10s  %8s  %8s  %8s  %10s  %s\n" \
        "$label" "${qps:-N/A}" "${kpps}" "${mbps}" "$(to_us "$lat_min")" "$(to_us "$avg")" "$(to_us "$lat_max")" "${avg_pct_us}" "${ok_pct}"
      ;;
  esac
}

print_header() {
  case "${BENCH_TYPE:-all}" in
    throughput)
      printf "  %-22s  %10s  %8s  %10s  %s\n" \
        "Test" "QPS" "Kpps" "Mbps" "OK%"
      printf "  %-22s  %10s  %8s  %10s  %s\n" \
        "----------------------" "----------" "--------" "----------" "------"
      ;;
    latency)
      printf "  %-22s  %8s  %8s  %8s  %10s  %s\n" \
        "Test" "Min(us)" "Avg(us)" "Max(us)" "P99(us)" "OK%"
      printf "  %-22s  %8s  %8s  %8s  %10s  %s\n" \
        "----------------------" "--------" "--------" "--------" "----------" "------"
      ;;
    *)
      printf "  %-22s  %10s  %8s  %10s  %8s  %8s  %8s  %10s  %s\n" \
        "Test" "QPS" "Kpps" "Mbps" "Min(us)" "Avg(us)" "Max(us)" "P99(us)" "OK%"
      printf "  %-22s  %10s  %8s  %10s  %8s  %8s  %8s  %10s  %s\n" \
        "----------------------" "----------" "--------" "----------" "--------" "--------" "--------" "----------" "------"
      ;;
  esac
}

collect_ztunnel_stats() {
  local phase="$1"
  echo ""
  echo "  ztunnel resource usage ($phase):"
  kubectl top pods -n istio-system -l app=ztunnel --no-headers 2>/dev/null | while IFS= read -r line; do
    printf "    %s\n" "$line"
  done || printf "    (metrics-server not available)\n"
}

print_report_header() {
  local bench_type="$1" topo="$2"
  local node_count
  node_count=$(kubectl get nodes --no-headers 2>/dev/null | wc -l | tr -d ' ')
  echo "========================================================================"
  echo "  ztunnel-testbed $bench_type Report"
  echo "  Generated: $(date)"
  echo "  Cluster: $(kubectl config current-context 2>/dev/null || echo unknown)"
  echo "  Nodes: $node_count   Topology: $topo"
  echo "  Mode: $MODE  Concurrency: $CONCURRENCY  Duration: $DURATION"
  echo "  Packet sizes: $PACKET_SIZES"
  echo "========================================================================"
}
