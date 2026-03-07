#!/usr/bin/env bash
# =============================================================================
# Functionality test: Pod -> Service -> Pod
# =============================================================================
# curl-client pod -> http-echo service (ClusterIP) -> http-echo pod
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib.sh"

test_start "Pod -> Service -> Pod"

client_pod=$(kubectl get pods -n sample-apps -l app=curl-client -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
[[ -n "$client_pod" ]] || fail "No curl-client pod found"

# Use Service DNS: http-echo.sample-apps.svc.cluster.local (or short http-echo)
result=$(kubectl exec -n sample-apps "$client_pod" -c curl -- curl -s -m 5 "http://http-echo.sample-apps.svc.cluster.local:80/" 2>/dev/null || echo "FAIL")
[[ "$result" == *"hello-from-pod"* ]] || fail "Expected 'hello-from-pod' via Service, got: $result"

pass "Pod -> Service -> Pod: http-echo service returned expected response"
