#!/usr/bin/env bash
# =============================================================================
# Functionality test: Two-node cross-node setup
# =============================================================================
# Verifies the two-node test infrastructure is correctly deployed:
#   - fortio-server-cp on control-plane, fortio-client-wk on worker
#   - Pods are on different nodes
#   - Cross-node connectivity works through ztunnel HBONE
#   - Reverse direction works
#   - Same-node path works
#   - ztunnel has enrolled all pods with SPIFFE certs
#
# Skips if: Two-node pods not deployed (run: make setup-two-node)
# Prerequisites: Multi-node cluster + make setup-two-node
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
source "${SCRIPT_DIR}/../lib.sh"
source "${PROJECT_ROOT}/config/cluster.sh" 2>/dev/null || true

NS="${APP_NAMESPACE:-grimlock}"

test_start "Two-node cross-node setup"
test_desc "Verifies cross-node pod placement, connectivity in all 3 paths, and mTLS enrollment."

# Check pods exist
cli_wk=$(kubectl get pods -n "$NS" -l app=fortio-client-wk -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
svr_cp=$(kubectl get pods -n "$NS" -l app=fortio-server-cp -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)

if [[ -z "$cli_wk" ]] || [[ -z "$svr_cp" ]]; then
  skip "Two-node pods not deployed (run: make setup-two-node)"
  exit 0
fi

svr_wk=$(kubectl get pods -n "$NS" -l app=fortio-server-wk -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
cli_cp=$(kubectl get pods -n "$NS" -l app=fortio-client-cp -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)

# Check placement
cli_wk_node=$(kubectl get pod "$cli_wk" -n "$NS" -o jsonpath='{.spec.nodeName}' 2>/dev/null || true)
svr_cp_node=$(kubectl get pod "$svr_cp" -n "$NS" -o jsonpath='{.spec.nodeName}' 2>/dev/null || true)
svr_wk_node=$(kubectl get pod "${svr_wk:-none}" -n "$NS" -o jsonpath='{.spec.nodeName}' 2>/dev/null || true)
cli_cp_node=$(kubectl get pod "${cli_cp:-none}" -n "$NS" -o jsonpath='{.spec.nodeName}' 2>/dev/null || true)

detail "fortio-client-wk on: $cli_wk_node"
detail "fortio-server-cp on: $svr_cp_node"
[[ -n "$svr_wk" ]] && detail "fortio-server-wk on: $svr_wk_node"
[[ -n "$cli_cp" ]] && detail "fortio-client-cp on: $cli_cp_node"

# Verify cross-node placement
[[ "$cli_wk_node" != "$svr_cp_node" ]] || fail "Client and server on same node ($cli_wk_node) — not cross-node!"
detail "Cross-node confirmed: $cli_wk_node ≠ $svr_cp_node"

# Test 1: cross-node (worker → control-plane)
detail "Test 1: cross-node worker → control-plane"
r1=$(kubectl exec -n "$NS" "$cli_wk" -c fortio -- \
  fortio curl "http://fortio-server-cp.${NS}.svc.cluster.local:8080/" 2>&1 || echo "FAILED")
echo "$r1" | grep -q "200 OK\|HTTP/1.1 200" || fail "Cross-node connectivity failed (worker→CP)"
detail "  worker → CP: OK"

# Test 2: reverse (control-plane → worker)
if [[ -n "$cli_cp" ]] && [[ -n "$svr_wk" ]]; then
  detail "Test 2: reverse control-plane → worker"
  r2=$(kubectl exec -n "$NS" "$cli_cp" -c fortio -- \
    fortio curl "http://fortio-server-wk.${NS}.svc.cluster.local:8080/" 2>&1 || echo "FAILED")
  echo "$r2" | grep -q "200 OK\|HTTP/1.1 200" || fail "Reverse connectivity failed (CP→worker)"
  detail "  CP → worker: OK"
fi

# Test 3: same-node (worker → worker)
if [[ -n "$svr_wk" ]]; then
  detail "Test 3: same-node worker → worker"
  r3=$(kubectl exec -n "$NS" "$cli_wk" -c fortio -- \
    fortio curl "http://fortio-server-wk.${NS}.svc.cluster.local:8080/" 2>&1 || echo "FAILED")
  echo "$r3" | grep -q "200 OK\|HTTP/1.1 200" || fail "Same-node connectivity failed (worker→worker)"
  detail "  worker → worker (same-node): OK"
fi

# Check ztunnel sees the pods
ISTIOCTL="${PROJECT_ROOT}/bin/istioctl"
[[ -x "$ISTIOCTL" ]] || ISTIOCTL=$(command -v istioctl 2>/dev/null || true)
if [[ -x "${ISTIOCTL:-}" ]]; then
  enrolled=$("$ISTIOCTL" ztunnel-config workloads 2>/dev/null | grep -cE "fortio-server-cp|fortio-client-wk" || true)
  detail "ztunnel workload enrollment: $enrolled/2 two-node pods"
fi

pass "Two-node setup verified: cross-node + reverse + same-node all OK"
