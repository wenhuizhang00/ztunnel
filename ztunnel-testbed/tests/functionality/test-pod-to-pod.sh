#!/usr/bin/env bash
# =============================================================================
# Functionality test: Pod-to-Pod direct connectivity
# =============================================================================
# curl-client pod -> http-echo pod IP directly (via ztunnel)
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
source "${SCRIPT_DIR}/../lib.sh"

test_start "Pod-to-Pod direct (curl -> http-echo pod IP)"

# Get a curl-client pod
client_pod=$(kubectl get pods -n grimlock -l app=curl-client -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
[[ -n "$client_pod" ]] || fail "No curl-client pod found"

# Get an http-echo pod IP
echo_pod_ip=$(kubectl get pods -n grimlock -l app=http-echo -o jsonpath='{.items[0].status.podIP}' 2>/dev/null)
[[ -n "$echo_pod_ip" ]] || fail "No http-echo pod IP found"

# Request to pod IP:8080 (http-echo listens on 8080)
result=$(kubectl exec -n grimlock "$client_pod" -c curl -- curl -s -m 5 "http://${echo_pod_ip}:8080/" 2>/dev/null || echo "FAIL")
[[ "$result" == *"hello-from-pod"* ]] || fail "Expected 'hello-from-pod' in response, got: $result"

pass "Pod-to-pod direct: curl -> ${echo_pod_ip}:8080 returned expected response"
