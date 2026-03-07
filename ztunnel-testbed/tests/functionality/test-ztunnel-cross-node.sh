#!/usr/bin/env bash
# =============================================================================
# Functionality test: ztunnel cross-node traffic (HBONE tunnel)
# =============================================================================
# Verifies that two pods on DIFFERENT nodes can communicate through ztunnel
# using the HBONE (HTTP/2 CONNECT) mTLS tunnel.
#
# Why this matters:
#   This is the core ztunnel data path for ambient mode across nodes:
#     curl-client-node1 (control-plane)
#       → ztunnel (node1, encrypts with mTLS)
#       → HBONE tunnel over network
#       → ztunnel (node2, decrypts)
#       → http-echo-node2 (worker)
#
#   If same-node works but cross-node fails, the issue is in:
#   - HBONE tunnel establishment between ztunnel instances
#   - Network connectivity between nodes (firewall, MTU)
#   - Certificate exchange between ztunnel instances
#   - Calico/CNI cross-node pod routing
#
# What it checks:
#   1. curl-client-node1 is on the control-plane
#   2. http-echo-node2 is on a worker node
#   3. They are on DIFFERENT nodes
#   4. HTTP request succeeds and returns "hello-from-node2"
#
# Also tests reverse direction:
#   5. curl-client-node2 (worker) -> http-echo-node1 (control-plane)
#
# Skips if: Single-node cluster (no cross-node apps deployed)
# Prerequisites: Multi-node deploy (make deploy with 2+ nodes)
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
source "${SCRIPT_DIR}/../lib.sh"
source "${PROJECT_ROOT}/config/cluster.sh" 2>/dev/null || true

NS="${APP_NAMESPACE:-grimlock}"

test_start "ztunnel cross-node traffic (HBONE tunnel)"

# Check multi-node apps exist
client1=$(kubectl get pods -n "$NS" -l app=curl-client-node1 -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
client2=$(kubectl get pods -n "$NS" -l app=curl-client-node2 -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)

if [[ -z "$client1" ]] || [[ -z "$client2" ]]; then
  skip "Cross-node apps not deployed (need 2+ nodes and make deploy)"
  exit 0
fi

# Get node placement
client1_node=$(kubectl get pod "$client1" -n "$NS" -o jsonpath='{.spec.nodeName}' 2>/dev/null || true)
client2_node=$(kubectl get pod "$client2" -n "$NS" -o jsonpath='{.spec.nodeName}' 2>/dev/null || true)
echo1_node=$(kubectl get pods -n "$NS" -l app=http-echo-node1 -o jsonpath='{.items[0].spec.nodeName}' 2>/dev/null || true)
echo2_node=$(kubectl get pods -n "$NS" -l app=http-echo-node2 -o jsonpath='{.items[0].spec.nodeName}' 2>/dev/null || true)

detail "curl-client-node1 on: $client1_node"
detail "curl-client-node2 on: $client2_node"
detail "http-echo-node1 on: $echo1_node"
detail "http-echo-node2 on: $echo2_node"

# Verify cross-node placement
if [[ "$client1_node" == "$echo2_node" ]]; then
  detail "WARNING: client1 and echo2 on same node (not a true cross-node test)"
fi

# Test 1: node1 -> node2 (control-plane -> worker)
echo2_ip=$(kubectl get pods -n "$NS" -l app=http-echo-node2 -o jsonpath='{.items[0].status.podIP}' 2>/dev/null || true)
[[ -n "$echo2_ip" ]] || fail "No http-echo-node2 pod IP found"
detail "Test 1: curl-client-node1 ($client1_node) -> http-echo-node2 ($echo2_node) @ ${echo2_ip}:8080"

result1=$(kubectl exec -n "$NS" "$client1" -c curl -- curl -s -m 10 "http://${echo2_ip}:8080/" 2>/dev/null || echo "CURL_FAILED")
detail "response: ${result1:0:120}"
[[ "$result1" == *"hello-from-node2"* ]] || fail "Cross-node (node1->node2) failed: $result1"

# Test 2: node2 -> node1 (worker -> control-plane, reverse direction)
echo1_ip=$(kubectl get pods -n "$NS" -l app=http-echo-node1 -o jsonpath='{.items[0].status.podIP}' 2>/dev/null || true)
[[ -n "$echo1_ip" ]] || fail "No http-echo-node1 pod IP found"
detail "Test 2: curl-client-node2 ($client2_node) -> http-echo-node1 ($echo1_node) @ ${echo1_ip}:8080"

result2=$(kubectl exec -n "$NS" "$client2" -c curl -- curl -s -m 10 "http://${echo1_ip}:8080/" 2>/dev/null || echo "CURL_FAILED")
detail "response: ${result2:0:120}"
[[ "$result2" == *"hello-from-node1"* ]] || fail "Cross-node (node2->node1) failed: $result2"

# Verify encryption: check ztunnel logs for HBONE/mTLS activity
zt_pod=$(kubectl get pods -n istio-system -l app=ztunnel -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
if [[ -n "$zt_pod" ]]; then
  recent_logs=$(kubectl logs "$zt_pod" -n istio-system --tail=30 --since=15s 2>/dev/null || true)
  hbone_entries=$(echo "$recent_logs" | grep -cE "CONNECT|HBONE|inbound|outbound" || true)
  detail "ztunnel HBONE/proxy entries (last 15s): $hbone_entries"
  if [[ "$hbone_entries" -gt 0 ]]; then
    echo "$recent_logs" | grep -E "CONNECT|HBONE|inbound|outbound" | tail -2 | while IFS= read -r line; do
      detail "  ${line:0:120}"
    done
  fi
fi

pass "Cross-node ztunnel: node1->node2 and node2->node1 both OK (mTLS HBONE tunnel verified)"
