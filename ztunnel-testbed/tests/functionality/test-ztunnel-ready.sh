#!/usr/bin/env bash
# =============================================================================
# Functionality test: ztunnel DaemonSet ready
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib.sh"

test_start "ztunnel DaemonSet ready"

kubectl get daemonset ztunnel -n istio-system &>/dev/null || fail "ztunnel DaemonSet not found"
desired=$(kubectl get daemonset ztunnel -n istio-system -o jsonpath='{.status.desiredNumberScheduled}' 2>/dev/null || echo 0)
ready=$(kubectl get daemonset ztunnel -n istio-system -o jsonpath='{.status.numberReady}' 2>/dev/null || echo 0)
[[ "${ready:-0}" -eq "${desired:-0}" ]] || fail "ztunnel not fully ready: $ready/$desired"

pass "ztunnel DaemonSet ready ($ready/$desired pods)"
