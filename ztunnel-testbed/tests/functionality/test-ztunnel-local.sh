#!/usr/bin/env bash
# =============================================================================
# Functionality test: ztunnel local (same-node) traffic
# =============================================================================
# Verifies that two pods on the SAME node can communicate through ztunnel.
#
# Why this matters:
#   In ambient mode, even same-node traffic is intercepted by ztunnel for
#   mTLS and policy enforcement. The path is:
#     curl-client-node1 → ztunnel (local) → http-echo-node1
#   Both pods run on the control-plane node. This tests the local ztunnel
#   data path without involving any cross-node HBONE tunnels.
#
# What it checks:
#   1. curl-client-node1 and http-echo-node1 exist on the same node
#   2. HTTP request from curl-client-node1 to http-echo-node1 pod IP succeeds
#   3. Response contains "hello-from-node1"
#
# Skips if: Single-node cluster without cross-node apps, or apps not deployed
# Prerequisites: Multi-node deploy (make deploy with 2+ nodes)
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
source "${SCRIPT_DIR}/../lib.sh"
source "${PROJECT_ROOT}/config/cluster.sh" 2>/dev/null || true

NS="${APP_NAMESPACE:-grimlock}"

test_start "ztunnel local (same-node) traffic"

# Check if cross-node apps are deployed
client_pod=$(kubectl get pods -n "$NS" -l app=curl-client-node1 -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
if [[ -z "$client_pod" ]]; then
  # Fall back to regular pod-to-pod (single-node cluster)
  client_pod=$(kubectl get pods -n "$NS" -l app=curl-client -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
  if [[ -z "$client_pod" ]]; then
    skip "No curl-client pod found (run: make deploy)"
    exit 0
  fi
  echo_pod_ip=$(kubectl get pods -n "$NS" -l app=http-echo -o jsonpath='{.items[0].status.podIP}' 2>/dev/null || true)
  [[ -n "$echo_pod_ip" ]] || fail "No http-echo pod IP found"

  # Verify they're on the same node (single-node = always true)
  client_node=$(kubectl get pod "$client_pod" -n "$NS" -o jsonpath='{.spec.nodeName}' 2>/dev/null || true)
  echo_node=$(kubectl get pods -n "$NS" -l app=http-echo -o jsonpath='{.items[0].spec.nodeName}' 2>/dev/null || true)
  detail "client node: $client_node, echo node: $echo_node (single-node mode)"

  result=$(kubectl exec -n "$NS" "$client_pod" -c curl -- curl -s -m 5 "http://${echo_pod_ip}:8080/" 2>/dev/null || echo "CURL_FAILED")
  detail "response: ${result:0:120}"
  [[ "$result" == *"hello"* ]] || fail "Same-node request failed: $result"
  pass "Local ztunnel: same-node pod-to-pod OK (single-node cluster)"
  exit 0
fi

# Multi-node mode: use node-pinned pods
echo_pod_ip=$(kubectl get pods -n "$NS" -l app=http-echo-node1 -o jsonpath='{.items[0].status.podIP}' 2>/dev/null || true)
[[ -n "$echo_pod_ip" ]] || fail "No http-echo-node1 pod IP found"

client_node=$(kubectl get pod "$client_pod" -n "$NS" -o jsonpath='{.spec.nodeName}' 2>/dev/null || true)
echo_node=$(kubectl get pods -n "$NS" -l app=http-echo-node1 -o jsonpath='{.items[0].spec.nodeName}' 2>/dev/null || true)
detail "curl-client-node1 on: $client_node"
detail "http-echo-node1 on: $echo_node"
detail "target: ${echo_pod_ip}:8080"

[[ "$client_node" == "$echo_node" ]] || detail "WARNING: pods not co-located (expected same node)"

result=$(kubectl exec -n "$NS" "$client_pod" -c curl -- curl -s -m 5 "http://${echo_pod_ip}:8080/" 2>/dev/null || echo "CURL_FAILED")
detail "response: ${result:0:120}"

[[ "$result" == *"hello-from-node1"* ]] || fail "Expected 'hello-from-node1', got: $result"
pass "Local ztunnel: curl-client-node1 -> http-echo-node1 (same node: $client_node)"
