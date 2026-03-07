#!/usr/bin/env bash
# =============================================================================
# Functionality test: Istiod ready
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib.sh"

test_start "Istiod ready"

kubectl get deployment istiod -n istio-system &>/dev/null || fail "istiod deployment not found"
ready=$(kubectl get deployment istiod -n istio-system -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo 0)
[[ "${ready:-0}" -ge 1 ]] || fail "istiod has no ready replicas"

pass "Istiod is ready (${ready} replica(s))"
