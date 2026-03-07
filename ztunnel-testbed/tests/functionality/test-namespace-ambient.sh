#!/usr/bin/env bash
# =============================================================================
# Functionality test: Namespace ambient label
# =============================================================================
# Verifies that the grimlock namespace has the Istio ambient dataplane-mode
# label applied.
#
# Why this matters:
#   Istio ambient mode is opt-in per namespace. The label
#   istio.io/dataplane-mode=ambient tells Istio to capture traffic from all
#   pods in that namespace via ztunnel. Without this label, pods in the
#   namespace are NOT part of the mesh — they get no mTLS, no L4 policy,
#   and no telemetry.
#
# What it checks:
#   1. grimlock namespace exists
#   2. Label istio.io/dataplane-mode is set to "ambient"
#
# Prerequisites: Sample apps deployed (make deploy)
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib.sh"

test_start "Namespace ambient label"

label=$(kubectl get namespace grimlock -o jsonpath='{.metadata.labels.istio\.io/dataplane-mode}' 2>/dev/null || true)
detail "grimlock istio.io/dataplane-mode: ${label:-<not set>}"

[[ "$label" == "ambient" ]] || fail "grimlock namespace missing istio.io/dataplane-mode=ambient (got: ${label:-<not set>})"

pass "grimlock has istio.io/dataplane-mode=ambient"
