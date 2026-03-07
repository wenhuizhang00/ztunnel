#!/usr/bin/env bash
# =============================================================================
# Functionality test: ztunnel DaemonSet ready
# =============================================================================
# Verifies that the ztunnel DaemonSet has all pods running and ready.
#
# Why this matters:
#   ztunnel is the per-node L4 proxy in Istio ambient mode. It handles mTLS
#   encryption, L4 authorization, and telemetry for all pods in ambient
#   namespaces. If ztunnel is not ready on a node, pods on that node have
#   no mesh connectivity.
#
# What it checks:
#   1. ztunnel DaemonSet exists in istio-system
#   2. numberReady == desiredNumberScheduled
#   3. Reports the ztunnel container image version
#
# Prerequisites: Istio installed (make install)
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib.sh"

test_start "ztunnel DaemonSet ready"

kubectl get daemonset ztunnel -n istio-system &>/dev/null || fail "ztunnel DaemonSet not found"
desired=$(kubectl get daemonset ztunnel -n istio-system -o jsonpath='{.status.desiredNumberScheduled}' 2>/dev/null || echo 0)
ready=$(kubectl get daemonset ztunnel -n istio-system -o jsonpath='{.status.numberReady}' 2>/dev/null || echo 0)
image=$(kubectl get daemonset ztunnel -n istio-system -o jsonpath='{.spec.template.spec.containers[0].image}' 2>/dev/null || echo unknown)
detail "ztunnel pods: $ready/$desired, image: $image"

[[ "${ready:-0}" -eq "${desired:-0}" ]] && [[ "${desired:-0}" -gt 0 ]] || fail "ztunnel not fully ready: $ready/$desired"
pass "ztunnel DaemonSet ready ($ready/$desired pods)"
