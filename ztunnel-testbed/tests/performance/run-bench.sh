#!/usr/bin/env bash
# =============================================================================
# ztunnel-testbed - Performance benchmark runner
# =============================================================================
# Modes: ambient | baseline | both
# Params: CONCURRENCY, REQUESTS, DURATION, OUTPUT_DIR
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
source "${PROJECT_ROOT}/scripts/common.sh"

# Defaults
MODE="${MODE:-both}"
CONCURRENCY="${CONCURRENCY:-4}"
REQUESTS="${REQUESTS:-5000}"
DURATION="${DURATION:-30s}"
OUTPUT_DIR="${OUTPUT_DIR:-${PROJECT_ROOT}/.bench-results}"
RUNS="${RUNS:-1}"

mkdir -p "$OUTPUT_DIR"
timestamp=$(date +%Y%m%d-%H%M%S)

ensure_kubectl_context

log_info "Performance benchmark: MODE=${MODE}, CONCURRENCY=${CONCURRENCY}, REQUESTS=${REQUESTS}"

# URLs (use APP_NAMESPACE from config)
AMBIENT_URL="http://http-echo.${APP_NAMESPACE}.svc.cluster.local:80/"
BASELINE_URL="http://http-echo.${APP_NAMESPACE_BASELINE}.svc.cluster.local:80/"

run_bench() {
  local name=$1
  local url=$2
  local client_ns=$3
  local out_file="${OUTPUT_DIR}/${name}-${timestamp}.txt"

  # Prefer fortio, fallback to curl-client with simple loop
  fortio_pod=$(kubectl get pods -n "${APP_NAMESPACE}" -l app=fortio -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
  curl_pod=$(kubectl get pods -n "$client_ns" -l app=curl-client -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
  client_pod="${fortio_pod:-$curl_pod}"
  [[ -n "$client_pod" ]] || { log_error "No client pod found"; return 1; }

  # Use fortio from grimlock (can reach both ambient and baseline via K8s network)
  if [[ -n "$fortio_pod" ]]; then
    log_step "BENCH" "[$name] Running fortio load test: $url"
    kubectl exec -n "${APP_NAMESPACE}" "$fortio_pod" -c fortio -- fortio load \
      -c "$CONCURRENCY" -n "$REQUESTS" -qps 0 -a \
      -json /tmp/out.json "$url" 2>&1 | tee "$out_file" || true
    # Try to extract key metrics
    kubectl exec -n "${APP_NAMESPACE}" "$fortio_pod" -c fortio -- cat /tmp/out.json 2>/dev/null >> "$out_file" || true
  else
    log_step "BENCH" "[$name] Running curl loop (basic, no fortio): $url"
    {
      echo "Benchmark: $name"
      echo "URL: $url"
      echo "Concurrency: $CONCURRENCY, Requests: $REQUESTS"
      echo "---"
      start=$(date +%s)
      ok=0; fail=0
      for i in $(seq 1 "$REQUESTS"); do
        kubectl exec -n "$client_ns" "$client_pod" -c curl -- curl -s -o /dev/null -w "%{time_total}\n" -m 5 "$url" 2>/dev/null && ok=$((ok+1)) || fail=$((fail+1))
      done
      end=$(date +%s)
      elapsed=$((end - start))
      [[ $elapsed -gt 0 ]] || elapsed=1
      qps=$((REQUESTS / elapsed))
      echo "OK: $ok, Failed: $fail"
      echo "Elapsed: ${elapsed}s"
      echo "QPS: $qps"
    } | tee "$out_file"
  fi
  log_step_ok "BENCH" "[$name] Results: $out_file"
}

if [[ "$MODE" == "ambient" ]]; then
  run_bench "ambient" "$AMBIENT_URL" "$APP_NAMESPACE"
elif [[ "$MODE" == "baseline" ]]; then
  run_bench "baseline" "$BASELINE_URL" "$APP_NAMESPACE"
else
  run_bench "ambient" "$AMBIENT_URL" "$APP_NAMESPACE"
  run_bench "baseline" "$BASELINE_URL" "$APP_NAMESPACE"
fi

log_ok "Benchmark complete. Results in ${OUTPUT_DIR}/"
