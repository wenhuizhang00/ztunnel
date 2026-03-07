#!/usr/bin/env bash
# =============================================================================
# Functionality test: Pod -> Service -> Pod
# =============================================================================
# Sends an HTTP request from curl-client through the http-echo ClusterIP
# Service, which load-balances to an http-echo pod.
#
# Why this matters:
#   This is the standard Kubernetes traffic path: pod -> Service -> pod.
#   In ambient mode, both hops go through ztunnel with mTLS. This test
#   verifies:
#   - CoreDNS resolves the service FQDN
#   - kube-proxy or ztunnel correctly NATs the ClusterIP to a pod IP
#   - ztunnel's HBONE tunnel carries the request end-to-end
#   If pod-to-pod works but pod-to-service fails, the issue is likely in
#   Service resolution (DNS or kube-proxy rules).
#
# What it checks:
#   1. curl-client pod exists
#   2. HTTP request to http-echo.grimlock.svc.cluster.local:80 returns expected response
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

test_start "Pod -> Service -> Pod"
test_desc "Sends HTTP request via ClusterIP Service. Tests DNS + kube-proxy + ztunnel end-to-end."

client_pod=$(kubectl get pods -n "$NS" -l app=curl-client -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
if [[ -z "$client_pod" ]]; then
  skip "No curl-client pod found in $NS (run: make deploy)"
  exit 0
fi

svc_ip=$(kubectl get svc http-echo -n "$NS" -o jsonpath='{.spec.clusterIP}' 2>/dev/null || true)
detail "client=$client_pod, service=http-echo.$NS (ClusterIP=${svc_ip:-N/A})"

result=$(kubectl exec -n "$NS" "$client_pod" -c curl -- curl -s -m 5 "http://http-echo.${NS}.svc.cluster.local:80/" 2>/dev/null || echo "CURL_FAILED")
detail "response: ${result:0:120}"

[[ "$result" == *"hello"* ]] || [[ "$result" == *"http-echo"* ]] || [[ "$result" == *"echo"* ]] || fail "Unexpected response via Service: $result"

pass "Pod -> Service -> Pod: http-echo service OK"
