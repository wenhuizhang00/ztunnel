#!/usr/bin/env bash
# =============================================================================
# Functionality test: CNI plugin ready
# =============================================================================
# Verifies the Istio CNI node agent (istio-cni-node) DaemonSet is fully
# rolled out on all nodes.
#
# Why this matters:
#   Istio ambient mode uses a CNI plugin to intercept pod traffic and redirect
#   it through ztunnel. If istio-cni-node is not running on a node, pods on
#   that node won't have their traffic captured by the mesh.
#
# What it checks:
#   1. istio-cni-node DaemonSet exists in istio-system
#   2. numberReady == desiredNumberScheduled (all nodes covered)
#
# Skips if: istio-cni-node DaemonSet not found (some setups use different CNI)
# Prerequisites: Istio installed (make install)
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib.sh"

test_start "CNI plugin ready"

if kubectl get daemonset istio-cni-node -n istio-system &>/dev/null; then
  desired=$(kubectl get daemonset istio-cni-node -n istio-system -o jsonpath='{.status.desiredNumberScheduled}' 2>/dev/null || echo 0)
  ready=$(kubectl get daemonset istio-cni-node -n istio-system -o jsonpath='{.status.numberReady}' 2>/dev/null || echo 0)
  detail "istio-cni-node: $ready/$desired pods ready"
  [[ "${ready:-0}" -eq "${desired:-0}" ]] && [[ "${desired:-0}" -gt 0 ]] || fail "istio-cni-node not fully ready: $ready/$desired"
else
  skip "istio-cni-node DaemonSet not found (may use different CNI)"
  exit 0
fi

pass "CNI plugin ready ($ready/$desired)"
