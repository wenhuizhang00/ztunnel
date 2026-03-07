#!/usr/bin/env bash
# =============================================================================
# Functionality test: DNS resolution inside pods
# =============================================================================
# Verifies that in-cluster DNS (CoreDNS) resolves service names from inside
# a pod in the ambient namespace.
#
# Why this matters:
#   Kubernetes services are accessed by DNS name (e.g. http-echo.grimlock).
#   If DNS is broken, pods can't discover other services. In ambient mode,
#   ztunnel intercepts L4 traffic but DNS still uses CoreDNS. This test
#   confirms DNS works end-to-end through the mesh.
#
# What it checks:
#   1. kubernetes.default.svc.cluster.local resolves (API server VIP)
#   2. http-echo.<namespace>.svc.cluster.local resolves
#
# Skips if: curl-client pod not found (run: make deploy)
# Prerequisites: Sample apps deployed
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
source "${SCRIPT_DIR}/../lib.sh"
source "${PROJECT_ROOT}/config/cluster.sh" 2>/dev/null || true

NS="${APP_NAMESPACE:-grimlock}"

test_start "DNS resolution inside pods"

client_pod=$(kubectl get pods -n "$NS" -l app=curl-client -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
if [[ -z "$client_pod" ]]; then
  skip "No curl-client pod found in $NS (run: make deploy)"
  exit 0
fi

detail "client pod: $client_pod"

# Test 1: Resolve kubernetes.default (the API server ClusterIP, always 10.96.0.1)
dns_result=$(kubectl exec -n "$NS" "$client_pod" -c curl -- \
  sh -c 'nslookup kubernetes.default.svc.cluster.local 2>/dev/null || getent hosts kubernetes.default.svc.cluster.local 2>/dev/null' \
  2>/dev/null || echo "DNS_FAILED")

detail "kubernetes.default lookup: ${dns_result:0:100}"
[[ "$dns_result" != "DNS_FAILED" ]] && [[ "$dns_result" == *"10.96.0.1"* || "$dns_result" == *"kubernetes"* ]] || fail "DNS resolution failed for kubernetes.default: $dns_result"

# Test 2: Resolve the http-echo service
svc_result=$(kubectl exec -n "$NS" "$client_pod" -c curl -- \
  sh -c "nslookup http-echo.${NS}.svc.cluster.local 2>/dev/null || getent hosts http-echo.${NS}.svc.cluster.local 2>/dev/null" \
  2>/dev/null || echo "DNS_FAILED")

detail "http-echo.$NS lookup: ${svc_result:0:100}"
[[ "$svc_result" != "DNS_FAILED" ]] && [[ -n "$svc_result" ]] || fail "DNS resolution failed for http-echo service"

pass "DNS resolution OK (kubernetes.default + http-echo.$NS)"
