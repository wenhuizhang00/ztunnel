#!/usr/bin/env bash
# =============================================================================
# Functionality test: Namespace ambient label
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib.sh"

test_start "Namespace ambient label"

# sample-apps namespace should have ambient label
label=$(kubectl get namespace sample-apps -o jsonpath='{.metadata.labels.istio\.io/dataplane-mode}' 2>/dev/null || true)
[[ "$label" == "ambient" ]] || fail "sample-apps namespace missing istio.io/dataplane-mode=ambient (got: ${label})"

pass "sample-apps has istio.io/dataplane-mode=ambient"
