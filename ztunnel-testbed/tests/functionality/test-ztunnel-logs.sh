#!/usr/bin/env bash
# =============================================================================
# Functionality test: ztunnel logs healthy
# =============================================================================
# Checks that ztunnel is not crash-looping and has no fatal errors in its
# recent log output.
#
# Why this matters:
#   A crash-looping ztunnel means the node's ambient mesh proxy is flapping.
#   Pods may lose mTLS connectivity intermittently, and new connections may
#   fail during restarts. Fatal errors (panics, segfaults) indicate a bug
#   in the ztunnel binary or a misconfiguration.
#
# What it checks:
#   1. ztunnel container restart count <= 2 (allows initial startup restarts)
#   2. No FATAL, panic, or segfault in the last 100 log lines
#
# Prerequisites: ztunnel running (make install)
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib.sh"

test_start "ztunnel logs healthy"
test_desc "Checks ztunnel is not crash-looping and has no FATAL errors in recent logs."

ztunnel_pod=$(kubectl get pods -n istio-system -l app=ztunnel -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
if [[ -z "$ztunnel_pod" ]]; then
  fail "No ztunnel pod found"
fi

# Check restart count (high restarts = crash loop)
restarts=$(kubectl get pod "$ztunnel_pod" -n istio-system -o jsonpath='{.status.containerStatuses[0].restartCount}' 2>/dev/null || echo 0)
detail "ztunnel pod: $ztunnel_pod"
detail "container restarts: ${restarts:-0}"

[[ "${restarts:-0}" -le 2 ]] || fail "ztunnel has $restarts restarts (possible crash loop)"

# Scan recent logs for fatal-level errors
error_count=$(kubectl logs "$ztunnel_pod" -n istio-system --tail=100 2>/dev/null | grep -ic "FATAL\|panic\|segfault" || true)
warn_count=$(kubectl logs "$ztunnel_pod" -n istio-system --tail=100 2>/dev/null | grep -ic "ERROR" || true)
detail "fatal/panic in last 100 lines: $error_count"
detail "ERROR-level in last 100 lines: $warn_count"

[[ "$error_count" -eq 0 ]] || fail "ztunnel has $error_count fatal errors in recent logs"

pass "ztunnel healthy (restarts: ${restarts:-0}, no fatal errors)"
