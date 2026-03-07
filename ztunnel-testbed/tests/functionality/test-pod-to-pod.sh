#!/usr/bin/env bash
# =============================================================================
# Functionality test: Pod-to-Pod direct connectivity
# =============================================================================
# Sends an HTTP request from curl-client to http-echo's pod IP directly.
#
# Why this matters:
#   In Istio ambient mode, traffic between pods on the same or different
#   nodes is intercepted by ztunnel and sent through an HBONE tunnel with
#   mTLS. This test verifies the full data path works:
#     curl-client → ztunnel (source) → HBONE tunnel → ztunnel (dest) → http-echo
#   If this fails but pod-to-service works, it may indicate an issue with
#   direct pod IP routing through ztunnel.
#
# What it checks:
#   1. curl-client pod exists in grimlock namespace
#   2. http-echo pod has a valid pod IP
#   3. HTTP request to pod_ip:8080 returns expected response
#
# Skips if: curl-client not deployed
# Prerequisites: make deploy
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
source "${SCRIPT_DIR}/../lib.sh"
source "${PROJECT_ROOT}/config/cluster.sh" 2>/dev/null || true

NS="${APP_NAMESPACE:-grimlock}"

test_start "Pod-to-Pod direct (curl -> http-echo pod IP)"

client_pod=$(kubectl get pods -n "$NS" -l app=curl-client -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
if [[ -z "$client_pod" ]]; then
  skip "No curl-client pod found in $NS (run: make deploy)"
  exit 0
fi

echo_pod_ip=$(kubectl get pods -n "$NS" -l app=http-echo -o jsonpath='{.items[0].status.podIP}' 2>/dev/null)
[[ -n "$echo_pod_ip" ]] || fail "No http-echo pod IP found"

detail "client=$client_pod, target=${echo_pod_ip}:8080"

result=$(kubectl exec -n "$NS" "$client_pod" -c curl -- curl -s -m 5 "http://${echo_pod_ip}:8080/" 2>/dev/null || echo "CURL_FAILED")
detail "response: ${result:0:120}"

[[ "$result" == *"hello"* ]] || [[ "$result" == *"http-echo"* ]] || [[ "$result" == *"echo"* ]] || fail "Unexpected response from pod IP: $result"

pass "Pod-to-pod direct: curl -> ${echo_pod_ip}:8080 OK"
